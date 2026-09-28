-- Additive RPS daily-goals schema and authenticated reward RPCs.
-- Progress is derived from completed server-written multiplayer history for the signed-in profile.
BEGIN;

DO $preflight$
BEGIN
  IF to_regclass('public.rps_players') IS NULL
     OR to_regclass('public.rps_match_history') IS NULL THEN
    RAISE EXCEPTION 'RPS daily goals require public.rps_players and public.rps_match_history';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='rps_players' AND column_name='id')
     OR NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='rps_players' AND column_name='auth_user_id')
     OR NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='rps_players' AND column_name='coins')
     OR NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='rps_players' AND column_name='updated_at')
     OR NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='rps_match_history' AND column_name='player_id')
     OR NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='rps_match_history' AND column_name='room_id')
     OR NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='rps_match_history' AND column_name='outcome')
     OR NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='rps_match_history' AND column_name='mode')
     OR NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='rps_match_history' AND column_name='played_at') THEN
    RAISE EXCEPTION 'RPS daily goals expected profile/history columns are missing';
  END IF;
END;
$preflight$;

-- Keep the source evidence and coin balance server-owned even if this migration is
-- reviewed/applied without the companion auth-cutover's equivalent table lockdown.
ALTER TABLE public.rps_match_history ENABLE ROW LEVEL SECURITY;
REVOKE ALL PRIVILEGES ON TABLE public.rps_match_history FROM PUBLIC, anon, authenticated;
ALTER TABLE public.rps_players ENABLE ROW LEVEL SECURITY;
REVOKE ALL PRIVILEGES ON TABLE public.rps_players FROM PUBLIC, anon, authenticated;

CREATE TABLE IF NOT EXISTS public.rps_daily_goal_claims (
  player_id uuid NOT NULL REFERENCES public.rps_players(id) ON DELETE CASCADE,
  goal_date date NOT NULL,
  goal_key text NOT NULL CHECK (goal_key IN ('play_1','play_3','win_1')),
  reward integer NOT NULL CHECK (reward IN (10,15,25)),
  claimed_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (player_id, goal_date, goal_key)
);

ALTER TABLE public.rps_daily_goal_claims ENABLE ROW LEVEL SECURITY;
-- RPC-only access; no client role gets direct table privileges or a write policy.
REVOKE ALL PRIVILEGES ON TABLE public.rps_daily_goal_claims FROM PUBLIC, anon, authenticated;
DO $policies$
DECLARE p record;
BEGIN
  FOR p IN SELECT policyname FROM pg_policies
    WHERE schemaname='public' AND tablename='rps_daily_goal_claims'
  LOOP
    EXECUTE format('DROP POLICY %I ON public.rps_daily_goal_claims',p.policyname);
  END LOOP;
END;
$policies$;

-- Internal builder; deliberately not executable by client roles. Uses current_date
-- passed by the public RPCs, matching rps_v2_claim_daily_login_reward().
CREATE OR REPLACE FUNCTION public.rps_v2_daily_goals_payload(
  p_player_id uuid, p_goal_date date, p_balance integer
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $function$
DECLARE
  v_matches integer := 0;
  v_wins integer := 0;
  v_goals jsonb;
BEGIN
  SELECT count(DISTINCT h.room_id)::integer,
         count(DISTINCT h.room_id) FILTER (WHERE lower(h.outcome)='win')::integer
    INTO v_matches, v_wins
  FROM public.rps_match_history h
  WHERE h.player_id=p_player_id
    AND h.room_id IS NOT NULL
    AND h.played_at::date=p_goal_date
    AND lower(coalesce(h.mode,'')) <> 'bot';

  SELECT jsonb_agg(jsonb_build_object(
    'key',g.goal_key,
    'title',g.title,
    'description',g.description,
    'progress',least(g.progress,g.target),
    'target',g.target,
    'reward',g.reward,
    'claimed',c.goal_key IS NOT NULL,
    'can_claim',(g.progress >= g.target AND c.goal_key IS NULL)
  ) ORDER BY g.sort_order)
  INTO v_goals
  FROM (VALUES
    (1,'play_1','Play 1 ranked match','Complete one multiplayer match today.',least(v_matches,1),1,10),
    (2,'play_3','Play 3 ranked matches','Complete three multiplayer matches today.',least(v_matches,3),3,15),
    (3,'win_1','Win 1 ranked match','Win one multiplayer match today.',least(v_wins,1),1,25)
  ) AS g(sort_order,goal_key,title,description,progress,target,reward)
  LEFT JOIN public.rps_daily_goal_claims c
    ON c.player_id=p_player_id AND c.goal_date=p_goal_date AND c.goal_key=g.goal_key;

  RETURN jsonb_build_object(
    'goal_date',p_goal_date,
    'current_balance',p_balance,
    'goals',coalesce(v_goals,'[]'::jsonb)
  );
END;
$function$;

CREATE OR REPLACE FUNCTION public.rps_v2_get_daily_goals()
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_player_id uuid;
  v_balance integer;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Authentication required' USING ERRCODE='28000'; END IF;
  SELECT p.id,p.coins INTO v_player_id,v_balance
  FROM public.rps_players p WHERE p.auth_user_id=v_uid;
  IF NOT FOUND THEN RAISE EXCEPTION 'Profile not found' USING ERRCODE='P0002'; END IF;
  RETURN public.rps_v2_daily_goals_payload(v_player_id,current_date,v_balance);
END;
$function$;

CREATE OR REPLACE FUNCTION public.rps_v2_claim_daily_goal(p_goal_key text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_player public.rps_players%ROWTYPE;
  v_today date := current_date;
  v_matches integer := 0;
  v_wins integer := 0;
  v_target integer;
  v_reward integer;
  v_progress integer;
  v_total_claimed integer := 0;
  v_rows integer;
  v_state jsonb;
  v_status text;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Authentication required' USING ERRCODE='28000'; END IF;
  IF p_goal_key IS NULL OR p_goal_key NOT IN ('play_1','play_3','win_1') THEN
    RAISE EXCEPTION 'Unknown daily goal' USING ERRCODE='22023';
  END IF;

  -- A per-player lock serializes simultaneous claims across all three goals.
  SELECT * INTO v_player FROM public.rps_players
    WHERE auth_user_id=v_uid FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Profile not found' USING ERRCODE='P0002'; END IF;

  SELECT count(DISTINCT h.room_id)::integer,
         count(DISTINCT h.room_id) FILTER (WHERE lower(h.outcome)='win')::integer
    INTO v_matches,v_wins
  FROM public.rps_match_history h
  WHERE h.player_id=v_player.id
    AND h.room_id IS NOT NULL
    AND h.played_at::date=v_today
    AND lower(coalesce(h.mode,'')) <> 'bot';

  SELECT coalesce(sum(c.reward),0)::integer INTO v_total_claimed
  FROM public.rps_daily_goal_claims c
  WHERE c.player_id=v_player.id AND c.goal_date=v_today;

  SELECT g.target,g.reward,g.progress INTO v_target,v_reward,v_progress
  FROM (VALUES
    ('play_1',1,10,least(v_matches,1)),
    ('play_3',3,15,least(v_matches,3)),
    ('win_1',1,25,least(v_wins,1))
  ) AS g(goal_key,target,reward,progress)
  WHERE g.goal_key=p_goal_key;

  IF EXISTS (SELECT 1 FROM public.rps_daily_goal_claims c
             WHERE c.player_id=v_player.id AND c.goal_date=v_today AND c.goal_key=p_goal_key) THEN
    v_status := 'already_claimed';
  ELSIF v_progress < v_target THEN
    v_status := 'not_ready';
  ELSIF v_total_claimed + v_reward > 50 THEN
    v_status := 'daily_cap_reached';
  ELSE
    INSERT INTO public.rps_daily_goal_claims(player_id,goal_date,goal_key,reward)
    VALUES(v_player.id,v_today,p_goal_key,v_reward)
    ON CONFLICT (player_id,goal_date,goal_key) DO NOTHING;
    GET DIAGNOSTICS v_rows=ROW_COUNT;
    IF v_rows=0 THEN
      v_status := 'already_claimed';
    ELSE
      UPDATE public.rps_players SET coins=coins+v_reward,updated_at=now()
      WHERE id=v_player.id RETURNING * INTO v_player;
      v_status := 'claimed';
    END IF;
  END IF;

  v_state := public.rps_v2_daily_goals_payload(v_player.id,v_today,v_player.coins);
  RETURN v_state || jsonb_build_object(
    'status',v_status,
    'reward',CASE WHEN v_status='claimed' THEN v_reward ELSE 0 END,
    'message',CASE v_status
      WHEN 'claimed' THEN 'Daily goal reward claimed.'
      WHEN 'already_claimed' THEN 'This daily goal was already claimed.'
      WHEN 'not_ready' THEN 'This daily goal is not complete yet.'
      ELSE 'The daily-goal reward limit has been reached.'
    END
  );
END;
$function$;

REVOKE ALL ON FUNCTION public.rps_v2_daily_goals_payload(uuid,date,integer) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.rps_v2_get_daily_goals() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.rps_v2_claim_daily_goal(text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.rps_v2_get_daily_goals() TO authenticated;
GRANT EXECUTE ON FUNCTION public.rps_v2_claim_daily_goal(text) TO authenticated;

NOTIFY pgrst, 'reload schema';
COMMIT;
