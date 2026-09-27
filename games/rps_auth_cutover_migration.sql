-- RPS Auth-backed gameplay and access-control cutover candidate.
-- NOT APPLIED. Validate against an isolated schema/data clone before any production change.
-- Guest rows stay in rps_players and continue to appear via rps_v2_get_leaderboard;
-- direct profile/room/history/chat/reward access is revoked in this cutover.
BEGIN;

-- Fail closed when assumed room/profile/history/reward schema differs.
DO $preflight$
DECLARE missing text;
BEGIN
  SELECT string_agg(req.table_name || '.' || req.column_name, ', ' ORDER BY req.table_name, req.column_name) INTO missing
  FROM (VALUES
    ('rps_players','id'),('rps_players','guest_token'),('rps_players','username'),('rps_players','avatar'),('rps_players','avatar_key'),('rps_players','username_changed_at'),('rps_players','created_at'),('rps_players','updated_at'),
    ('rps_players','wins'),('rps_players','losses'),('rps_players','draws'),('rps_players','xp'),('rps_players','level'),('rps_players','coins'),('rps_players','current_streak'),('rps_players','best_streak'),
    ('rps_rooms','id'),('rps_rooms','room_code'),('rps_rooms','p1_id'),('rps_rooms','p1_name'),('rps_rooms','p2_id'),('rps_rooms','p2_name'),
    ('rps_rooms','status'),('rps_rooms','round_number'),('rps_rooms','p1_move'),('rps_rooms','p2_move'),('rps_rooms','result'),
    ('rps_rooms','winner_id'),('rps_rooms','p1_score'),('rps_rooms','p2_score'),
    ('rps_match_history','room_id'),('rps_match_history','player_id'),('rps_match_history','opponent_name'),('rps_match_history','outcome'),('rps_match_history','mode'),('rps_match_history','played_at'),
    ('rps_share_rewards','player_id'),('rps_share_rewards','reward_date'),('rps_share_rewards','reward')
  ) AS req(table_name,column_name)
  LEFT JOIN information_schema.columns c ON c.table_schema='public' AND c.table_name=req.table_name AND c.column_name=req.column_name
  WHERE c.column_name IS NULL;
  IF missing IS NOT NULL THEN RAISE EXCEPTION 'RPS secure migration does not match this schema; missing: %', missing; END IF;
  IF EXISTS (SELECT 1 FROM public.rps_match_history GROUP BY room_id,player_id HAVING count(*) > 1) THEN
    RAISE EXCEPTION 'RPS secure migration requires unique (room_id, player_id) match-history rows';
  END IF;
  IF EXISTS (SELECT 1 FROM public.rps_players GROUP BY lower(username) HAVING count(*) > 1) THEN
    RAISE EXCEPTION 'RPS secure migration requires case-insensitive unique usernames; review legacy duplicates before retrying';
  END IF;
END;
$preflight$;

ALTER TABLE public.rps_rooms
  ADD COLUMN IF NOT EXISTS mode text NOT NULL DEFAULT 'unlimited',
  ADD COLUMN IF NOT EXISTS max_rounds integer,
  ADD COLUMN IF NOT EXISTS max_players smallint NOT NULL DEFAULT 2,
  ADD COLUMN IF NOT EXISTS p3_id text, ADD COLUMN IF NOT EXISTS p3_name text,
  ADD COLUMN IF NOT EXISTS p3_player_id uuid REFERENCES public.rps_players(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS p3_move text, ADD COLUMN IF NOT EXISTS p3_score integer NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS p1_player_id uuid REFERENCES public.rps_players(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS p2_player_id uuid REFERENCES public.rps_players(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS winner_ids text[] NOT NULL DEFAULT ARRAY[]::text[],
  ADD COLUMN IF NOT EXISTS match_finished_at timestamptz,
  ADD COLUMN IF NOT EXISTS match_winner_ids text[] NOT NULL DEFAULT ARRAY[]::text[];

ALTER TABLE public.rps_players ADD COLUMN IF NOT EXISTS auth_user_id uuid REFERENCES auth.users(id) ON DELETE SET NULL;
CREATE UNIQUE INDEX IF NOT EXISTS rps_players_auth_user_id_uidx ON public.rps_players(auth_user_id) WHERE auth_user_id IS NOT NULL;
-- Legacy guest profiles may already have duplicate display names. Enforce uniqueness
-- only among new Auth-owned profiles; profile RPCs below also prevent new names from
-- colliding with any legacy row.
CREATE UNIQUE INDEX IF NOT EXISTS rps_players_username_ci_uidx
  ON public.rps_players(lower(username)) WHERE auth_user_id IS NOT NULL;
-- Reuse the exact existing unique-index names so we do not add redundant indexes.
CREATE UNIQUE INDEX IF NOT EXISTS rps_match_history_room_id_player_id_key
  ON public.rps_match_history(room_id,player_id);
CREATE UNIQUE INDEX IF NOT EXISTS rps_share_rewards_player_id_reward_date_key
  ON public.rps_share_rewards(player_id,reward_date);
ALTER TABLE public.rps_rooms ADD COLUMN IF NOT EXISTS round_winner_player_ids uuid[] NOT NULL DEFAULT ARRAY[]::uuid[];

-- Never cut over while a guest/legacy match is active; this keeps existing sessions from being stranded.
DO $active_room_check$
BEGIN
  IF EXISTS (
    SELECT 1 FROM public.rps_rooms r
    LEFT JOIN public.rps_players p1 ON p1.id=r.p1_player_id
    LEFT JOIN public.rps_players p2 ON p2.id=r.p2_player_id
    LEFT JOIN public.rps_players p3 ON p3.id=r.p3_player_id
    WHERE r.status IN ('waiting','playing')
      AND (p1.auth_user_id IS NULL OR (r.p2_player_id IS NOT NULL AND p2.auth_user_id IS NULL)
        OR (r.p3_player_id IS NOT NULL AND p3.auth_user_id IS NULL))
  ) THEN RAISE EXCEPTION 'Drain or explicitly resolve legacy guest rooms before the RPS security cutover'; END IF;
END;
$active_room_check$;

-- Separate room chat from the pre-existing rps_messages direct-message schema.
CREATE TABLE IF NOT EXISTS public.rps_room_messages (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  room_id uuid NOT NULL REFERENCES public.rps_rooms(id) ON DELETE CASCADE,
  player_id uuid NOT NULL REFERENCES public.rps_players(id) ON DELETE CASCADE,
  player_name text NOT NULL, message text NOT NULL CHECK (char_length(message) BETWEEN 1 AND 240),
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS rps_room_messages_room_created_idx ON public.rps_room_messages(room_id,created_at,id);

-- Identity is additive and nullable so the five legacy profiles remain unchanged.
ALTER TABLE public.rps_players
  ADD COLUMN IF NOT EXISTS auth_user_id uuid REFERENCES auth.users(id) ON DELETE SET NULL;

CREATE UNIQUE INDEX IF NOT EXISTS rps_players_auth_user_id_uidx
  ON public.rps_players(auth_user_id)
  WHERE auth_user_id IS NOT NULL;

-- New server-owned resolution field; legacy winner columns stay in place for old rows.
ALTER TABLE public.rps_rooms
  ADD COLUMN IF NOT EXISTS round_winner_player_ids uuid[] NOT NULL DEFAULT ARRAY[]::uuid[];

-- Profile load/create. Caller can set presentation fields only; identity, token, and
-- all progression/balance fields are server generated or left at database defaults.
CREATE OR REPLACE FUNCTION public.rps_v2_get_or_create_profile(
  p_username text,
  p_avatar_key text DEFAULT 'starter'
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_player public.rps_players%ROWTYPE;
  v_username text := btrim(coalesce(p_username, ''));
  v_avatar text := coalesce(nullif(btrim(p_avatar_key), ''), '🦊');
  v_avatar_key text;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'Authentication required' USING ERRCODE='28000';
  END IF;
  IF char_length(v_username) < 1 OR char_length(v_username) > 24
     OR v_username !~ '^[A-Za-z0-9 _.-]+$' THEN
    RAISE EXCEPTION 'Invalid display name' USING ERRCODE='22023';
  END IF;
  IF v_avatar NOT IN ('starter','rock','paper','scissors','🦊','🐼','🐸','🐯','🐙') THEN
    RAISE EXCEPTION 'Invalid avatar key' USING ERRCODE='22023';
  END IF;
  v_avatar_key := CASE WHEN v_avatar IN ('starter','rock','paper','scissors') THEN v_avatar ELSE 'starter' END;
  IF v_avatar IN ('starter','rock','paper','scissors') THEN v_avatar := '🦊'; END IF;

  IF NOT EXISTS (SELECT 1 FROM public.rps_players WHERE auth_user_id = v_uid)
     AND EXISTS (SELECT 1 FROM public.rps_players WHERE lower(username) = lower(v_username)
                 AND auth_user_id IS DISTINCT FROM v_uid) THEN
    RAISE EXCEPTION 'Username is already in use' USING ERRCODE='23505';
  END IF;

  INSERT INTO public.rps_players (auth_user_id, guest_token, username, avatar_key, avatar)
  VALUES (v_uid, gen_random_uuid()::text, v_username, v_avatar_key, v_avatar)
  ON CONFLICT (auth_user_id) WHERE auth_user_id IS NOT NULL
  DO UPDATE SET updated_at = now()
  RETURNING * INTO v_player;

  RETURN jsonb_build_object(
    'player_id', v_player.id,
    'username', v_player.username,
    'avatar', v_player.avatar,
    'avatar_key', v_player.avatar_key,
    'username_changed_at', v_player.username_changed_at,
    'coins', v_player.coins,
    'xp', v_player.xp,
    'level', v_player.level,
    'wins', v_player.wins,
    'losses', v_player.losses,
    'draws', v_player.draws
  );
END;
$function$;

-- Create a room with a server-generated code and a caller-derived seat 1.
CREATE OR REPLACE FUNCTION public.rps_v2_create_room(
  p_max_players smallint,
  p_mode text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_player public.rps_players%ROWTYPE;
  v_room public.rps_rooms%ROWTYPE;
  v_code text;
  v_max_rounds integer;
  v_attempt integer := 0;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'Authentication required' USING ERRCODE='28000';
  END IF;
  IF p_max_players IS NULL OR p_max_players NOT IN (2,3) THEN
    RAISE EXCEPTION 'Unsupported room capacity' USING ERRCODE='22023';
  END IF;
  IF p_mode IS NULL OR p_mode NOT IN ('unlimited','best3','best5','best10') THEN
    RAISE EXCEPTION 'Unsupported match mode' USING ERRCODE='22023';
  END IF;

  SELECT * INTO v_player
  FROM public.rps_players
  WHERE auth_user_id = v_uid
  FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Create/load a free-play profile first' USING ERRCODE='P0002';
  END IF;

  v_max_rounds := CASE p_mode
    WHEN 'best3' THEN 3 WHEN 'best5' THEN 5 WHEN 'best10' THEN 10 ELSE NULL END;

  LOOP
    v_attempt := v_attempt + 1;
    IF v_attempt > 5 THEN
      RAISE EXCEPTION 'Could not allocate a room code';
    END IF;
    v_code := upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 6));
    BEGIN
      INSERT INTO public.rps_rooms (
        room_code, max_players, p1_id, p1_name, p1_player_id,
        status, round_number, mode, max_rounds
      ) VALUES (
        v_code, p_max_players, v_player.id::text, v_player.username, v_player.id,
        'waiting', 1, p_mode, v_max_rounds
      ) RETURNING * INTO v_room;
      EXIT;
    EXCEPTION WHEN unique_violation THEN
      -- Retry only room-code collisions; all other constraints should surface.
      IF v_attempt >= 5 THEN RAISE; END IF;
    END;
  END LOOP;

  RETURN jsonb_build_object('room_id',v_room.id,'room_code',v_room.room_code,
    'status',v_room.status,'max_players',v_room.max_players);
END;
$function$;

-- Join by code only. Row lock prevents two callers taking the same seat.
CREATE OR REPLACE FUNCTION public.rps_v2_join_room(p_room_code text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_player public.rps_players%ROWTYPE;
  v_room public.rps_rooms%ROWTYPE;
  v_slot smallint;
  v_status text;
  v_already_seated boolean := false;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'Authentication required' USING ERRCODE='28000';
  END IF;
  IF p_room_code IS NULL OR char_length(btrim(p_room_code)) NOT BETWEEN 4 AND 12 THEN
    RAISE EXCEPTION 'Invalid room code' USING ERRCODE='22023';
  END IF;
  SELECT * INTO v_player FROM public.rps_players WHERE auth_user_id=v_uid FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Create/load a free-play profile first' USING ERRCODE='P0002'; END IF;

  SELECT * INTO v_room FROM public.rps_rooms
  WHERE room_code=upper(btrim(p_room_code))
  FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Room not found' USING ERRCODE='P0002'; END IF;

  IF v_room.p1_player_id=v_player.id THEN v_slot:=1; v_already_seated:=true;
  ELSIF v_room.p2_player_id=v_player.id THEN v_slot:=2; v_already_seated:=true;
  ELSIF v_room.p3_player_id=v_player.id THEN v_slot:=3; v_already_seated:=true;
  ELSE
    IF v_room.status<>'waiting' THEN RAISE EXCEPTION 'Room is not accepting players' USING ERRCODE='55000'; END IF;
    IF v_room.p2_player_id IS NULL THEN v_slot:=2;
    ELSIF v_room.max_players=3 AND v_room.p3_player_id IS NULL THEN v_slot:=3;
    ELSE RAISE EXCEPTION 'Room is full' USING ERRCODE='23514';
    END IF;
  END IF;

  IF NOT v_already_seated AND v_slot=2 AND v_room.p2_player_id IS NULL THEN
    UPDATE public.rps_rooms SET p2_id=v_player.id::text, p2_name=v_player.username,
      p2_player_id=v_player.id,
      status=CASE WHEN v_room.max_players=2 THEN 'playing' ELSE 'waiting' END
    WHERE id=v_room.id;
  ELSIF v_slot=3 AND v_room.p3_player_id IS NULL THEN
    UPDATE public.rps_rooms SET p3_id=v_player.id::text, p3_name=v_player.username,
      p3_player_id=v_player.id, status='playing'
    WHERE id=v_room.id;
  END IF;

  SELECT status INTO v_status FROM public.rps_rooms WHERE id=v_room.id;
  RETURN jsonb_build_object('room_id',v_room.id,'room_code',v_room.room_code,
                            'player_slot',v_slot,'status',v_status,
                            'max_players',v_room.max_players);
END;
$function$;

-- Sanitized participant-only room view; opposing moves are masked until resolution.
CREATE OR REPLACE FUNCTION public.rps_v2_get_room_state(p_room_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_player public.rps_players%ROWTYPE;
  v_room public.rps_rooms%ROWTYPE;
  v_slot smallint;
  v_reveal boolean;
  v_players jsonb;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Authentication required' USING ERRCODE='28000'; END IF;
  SELECT * INTO v_player FROM public.rps_players WHERE auth_user_id=v_uid;
  IF NOT FOUND THEN RAISE EXCEPTION 'Profile not found' USING ERRCODE='P0002'; END IF;
  SELECT * INTO v_room FROM public.rps_rooms WHERE id=p_room_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Room not found' USING ERRCODE='P0002'; END IF;

  v_slot := CASE WHEN v_room.p1_player_id=v_player.id THEN 1
                 WHEN v_room.p2_player_id=v_player.id THEN 2
                 WHEN v_room.p3_player_id=v_player.id THEN 3 ELSE NULL END;
  IF v_slot IS NULL THEN RAISE EXCEPTION 'Not a room participant' USING ERRCODE='42501'; END IF;
  v_reveal := v_room.result IS NOT NULL;

  SELECT coalesce(jsonb_agg(jsonb_build_object(
    'slot',s.slot, 'name',s.display_name, 'score',s.score,
    'has_moved',(s.move IS NOT NULL),
    'move',CASE WHEN v_reveal OR s.player_id=v_player.id THEN s.move ELSE NULL END,
    'round_winner',(s.player_id=ANY(v_room.round_winner_player_ids))
  ) ORDER BY s.slot),'[]'::jsonb)
  INTO v_players
  FROM (VALUES
    (1::smallint,v_room.p1_player_id,v_room.p1_name,v_room.p1_move,v_room.p1_score),
    (2::smallint,v_room.p2_player_id,v_room.p2_name,v_room.p2_move,v_room.p2_score),
    (3::smallint,v_room.p3_player_id,v_room.p3_name,v_room.p3_move,v_room.p3_score)
  ) AS s(slot,player_id,display_name,move,score)
  WHERE s.player_id IS NOT NULL;

  RETURN jsonb_build_object(
    'id',v_room.id,'room_id',v_room.id,'room_code',v_room.room_code,
    'status',v_room.status,'mode',v_room.mode,'max_rounds',v_room.max_rounds,
    'max_players',v_room.max_players,'round_number',v_room.round_number,
    'p1_id',v_room.p1_player_id::text,'p1_name',v_room.p1_name,
    'p2_id',v_room.p2_player_id::text,'p2_name',v_room.p2_name,
    'p3_id',v_room.p3_player_id::text,'p3_name',v_room.p3_name,
    'p1_move',CASE WHEN v_reveal OR v_slot=1 THEN v_room.p1_move ELSE NULL END,
    'p2_move',CASE WHEN v_reveal OR v_slot=2 THEN v_room.p2_move ELSE NULL END,
    'p3_move',CASE WHEN v_reveal OR v_slot=3 THEN v_room.p3_move ELSE NULL END,
    'p1_score',v_room.p1_score,'p2_score',v_room.p2_score,'p3_score',v_room.p3_score,
    'result',CASE WHEN v_reveal THEN v_room.result ELSE NULL END,
    'winner_id',CASE WHEN v_reveal THEN v_room.winner_id ELSE NULL END,
    'winner_ids',CASE WHEN v_reveal THEN v_room.winner_ids ELSE ARRAY[]::text[] END,
    'my_slot',v_slot,'players',v_players,'match_finished',(v_room.match_finished_at IS NOT NULL),
    'match_finished_at',v_room.match_finished_at,'match_winner_ids',v_room.match_winner_ids
  );
END;
$function$;

-- Submit a single move and resolve the round atomically after all active seats move.
CREATE OR REPLACE FUNCTION public.rps_v2_submit_move(p_room_id uuid,p_move text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_player public.rps_players%ROWTYPE;
  v_room public.rps_rooms%ROWTYPE;
  v_slot smallint;
  v_old_move text;
  v_distinct_moves integer;
  v_has_rock boolean;
  v_has_paper boolean;
  v_has_scissors boolean;
  v_winning_move text;
  v_winners uuid[] := ARRAY[]::uuid[];
  v_result text;
  v_current_round integer;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Authentication required' USING ERRCODE='28000'; END IF;
  IF p_move IS NULL OR p_move NOT IN ('rock','paper','scissors') THEN RAISE EXCEPTION 'Invalid move' USING ERRCODE='22023'; END IF;
  SELECT * INTO v_player FROM public.rps_players WHERE auth_user_id=v_uid;
  IF NOT FOUND THEN RAISE EXCEPTION 'Profile not found' USING ERRCODE='P0002'; END IF;
  SELECT * INTO v_room FROM public.rps_rooms WHERE id=p_room_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Room not found' USING ERRCODE='P0002'; END IF;
  v_slot := CASE WHEN v_room.p1_player_id=v_player.id THEN 1
                 WHEN v_room.p2_player_id=v_player.id THEN 2
                 WHEN v_room.p3_player_id=v_player.id THEN 3 ELSE NULL END;
  IF v_slot IS NULL THEN RAISE EXCEPTION 'Not a room participant' USING ERRCODE='42501'; END IF;
  v_old_move := CASE v_slot WHEN 1 THEN v_room.p1_move WHEN 2 THEN v_room.p2_move ELSE v_room.p3_move END;
  IF v_old_move IS NOT NULL AND v_old_move<>p_move THEN
    RAISE EXCEPTION 'Move already locked for this round' USING ERRCODE='55000';
  END IF;
  IF v_room.result IS NOT NULL OR v_room.match_finished_at IS NOT NULL THEN
    IF v_old_move=p_move THEN RETURN public.rps_v2_get_room_state(p_room_id); END IF;
    RAISE EXCEPTION 'Round is already resolved' USING ERRCODE='55000';
  END IF;
  IF v_room.status<>'playing' THEN RAISE EXCEPTION 'Room is not accepting a move' USING ERRCODE='55000'; END IF;
  IF v_old_move IS NULL THEN
    IF v_slot=1 THEN UPDATE public.rps_rooms SET p1_move=p_move WHERE id=v_room.id;
    ELSIF v_slot=2 THEN UPDATE public.rps_rooms SET p2_move=p_move WHERE id=v_room.id;
    ELSE UPDATE public.rps_rooms SET p3_move=p_move WHERE id=v_room.id;
    END IF;
  END IF;

  SELECT * INTO v_room FROM public.rps_rooms WHERE id=p_room_id FOR UPDATE;
  IF v_room.p1_move IS NULL OR v_room.p2_move IS NULL
     OR (v_room.max_players=3 AND (v_room.p3_player_id IS NULL OR v_room.p3_move IS NULL)) THEN
    RETURN public.rps_v2_get_room_state(p_room_id);
  END IF;

  SELECT count(DISTINCT m) INTO v_distinct_moves
  FROM (VALUES (v_room.p1_move),(v_room.p2_move),
        (CASE WHEN v_room.max_players=3 THEN v_room.p3_move ELSE NULL END)) AS moves(m)
  WHERE m IS NOT NULL;

  IF v_distinct_moves=2 THEN
    SELECT bool_or(m='rock'),bool_or(m='paper'),bool_or(m='scissors')
      INTO v_has_rock,v_has_paper,v_has_scissors
    FROM (VALUES (v_room.p1_move),(v_room.p2_move),
          (CASE WHEN v_room.max_players=3 THEN v_room.p3_move ELSE NULL END)) AS moves(m)
    WHERE m IS NOT NULL;
    v_winning_move := CASE
      WHEN v_has_rock AND v_has_paper THEN 'paper'
      WHEN v_has_rock AND v_has_scissors THEN 'rock'
      ELSE 'scissors' END;
    SELECT coalesce(array_agg(player_id ORDER BY slot),ARRAY[]::uuid[])
      INTO v_winners
    FROM (VALUES
      (1::smallint,v_room.p1_player_id,v_room.p1_move),
      (2::smallint,v_room.p2_player_id,v_room.p2_move),
      (3::smallint,v_room.p3_player_id,v_room.p3_move)
    ) AS s(slot,player_id,move)
    WHERE s.player_id IS NOT NULL AND s.move=v_winning_move;
  END IF;

  v_result := CASE
    WHEN cardinality(v_winners)=0 THEN 'draw'
    WHEN cardinality(v_winners)>1 THEN 'multi'
    WHEN v_winners[1]=v_room.p1_player_id THEN 'p1'
    WHEN v_winners[1]=v_room.p2_player_id THEN 'p2'
    ELSE 'p3' END;

  UPDATE public.rps_rooms SET
    result=v_result,
    winner_id=CASE WHEN cardinality(v_winners)=1 THEN v_winners[1]::text ELSE NULL END,
    winner_ids=ARRAY(SELECT unnest(v_winners)::text),
    round_winner_player_ids=v_winners,
    p1_score=p1_score+CASE WHEN v_room.p1_player_id=ANY(v_winners) THEN 1 ELSE 0 END,
    p2_score=p2_score+CASE WHEN v_room.p2_player_id=ANY(v_winners) THEN 1 ELSE 0 END,
    p3_score=p3_score+CASE WHEN v_room.p3_player_id=ANY(v_winners) THEN 1 ELSE 0 END
  WHERE id=v_room.id AND round_number=v_room.round_number AND result IS NULL;
  GET DIAGNOSTICS v_current_round=ROW_COUNT;
  IF v_current_round<>1 THEN RAISE EXCEPTION 'Round changed concurrently; retry state read' USING ERRCODE='40001'; END IF;
  RETURN public.rps_v2_get_room_state(p_room_id);
END;
$function$;

-- Start the next round only after the current server-resolved round, before match end.
CREATE OR REPLACE FUNCTION public.rps_v2_advance_round(p_room_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_player public.rps_players%ROWTYPE;
  v_room public.rps_rooms%ROWTYPE;
  v_top integer;
  v_target integer;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Authentication required' USING ERRCODE='28000'; END IF;
  SELECT * INTO v_player FROM public.rps_players WHERE auth_user_id=v_uid;
  IF NOT FOUND THEN RAISE EXCEPTION 'Profile not found' USING ERRCODE='P0002'; END IF;
  SELECT * INTO v_room FROM public.rps_rooms WHERE id=p_room_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Room not found' USING ERRCODE='P0002'; END IF;
  IF NOT (v_player.id = ANY(array_remove(ARRAY[v_room.p1_player_id,v_room.p2_player_id,v_room.p3_player_id]::uuid[],NULL))) THEN
    RAISE EXCEPTION 'Not a room participant' USING ERRCODE='42501';
  END IF;
  IF v_room.status<>'playing' OR v_room.result IS NULL OR v_room.match_finished_at IS NOT NULL THEN
    RAISE EXCEPTION 'Round is not ready to advance' USING ERRCODE='55000';
  END IF;
  IF v_room.max_rounds IS NOT NULL THEN
    v_target:=floor(v_room.max_rounds::numeric/2)::integer+1;
    v_top:=greatest(v_room.p1_score,v_room.p2_score,v_room.p3_score);
    IF v_top>=v_target OR v_room.round_number>=v_room.max_rounds THEN
      RAISE EXCEPTION 'Match is complete; finalize it instead' USING ERRCODE='55000';
    END IF;
  END IF;
  UPDATE public.rps_rooms SET round_number=round_number+1,
    p1_move=NULL,p2_move=NULL,p3_move=NULL,result=NULL,winner_id=NULL,
    winner_ids=ARRAY[]::text[],round_winner_player_ids=ARRAY[]::uuid[]
  WHERE id=v_room.id;
  RETURN public.rps_v2_get_room_state(p_room_id);
END;
$function$;

-- Finalize only a server-complete Best-of match. No force/guest/player/result/score inputs.
CREATE OR REPLACE FUNCTION public.rps_v2_finalize_match(p_room_id uuid,p_allow_leave boolean DEFAULT false)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_player public.rps_players%ROWTYPE;
  v_room public.rps_rooms%ROWTYPE;
  v_player_ids uuid[];
  v_winners uuid[] := ARRAY[]::uuid[];
  v_top integer;
  v_target integer;
  v_completed_rounds integer;
  v_outcome text;
  v_opponents text;
  v_xp integer;
  v_coins integer;
  v_rows integer;
  v_match_winner_ids text[] := ARRAY[]::text[];
  v_finished_at timestamptz := now();
  v_participant record;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Authentication required' USING ERRCODE='28000'; END IF;
  SELECT * INTO v_player FROM public.rps_players WHERE auth_user_id=v_uid;
  IF NOT FOUND THEN RAISE EXCEPTION 'Profile not found' USING ERRCODE='P0002'; END IF;
  SELECT * INTO v_room FROM public.rps_rooms WHERE id=p_room_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Room not found' USING ERRCODE='P0002'; END IF;
  IF NOT (v_player.id = ANY(array_remove(ARRAY[v_room.p1_player_id,v_room.p2_player_id,v_room.p3_player_id]::uuid[],NULL))) THEN
    RAISE EXCEPTION 'Not a room participant' USING ERRCODE='42501';
  END IF;
  IF v_room.match_finished_at IS NOT NULL THEN
    RETURN jsonb_build_object('finished',true,'already_finished',true,
                              'match_finished_at',v_room.match_finished_at);
  END IF;
  IF v_room.status<>'playing' THEN
    RAISE EXCEPTION 'Room is not active' USING ERRCODE='55000';
  END IF;
  v_completed_rounds:=CASE WHEN v_room.result IS NOT NULL THEN v_room.round_number ELSE greatest(v_room.round_number-1,0) END;
  v_top:=greatest(v_room.p1_score,v_room.p2_score,v_room.p3_score);
  IF v_completed_rounds=0 AND p_allow_leave THEN
    UPDATE public.rps_rooms SET status='closed',match_finished_at=now(),match_winner_ids=ARRAY[]::text[] WHERE id=v_room.id;
    RETURN jsonb_build_object('finished',true,'already_finished',false,'winner_count',0,'completed_rounds',0);
  END IF;
  IF NOT p_allow_leave THEN
    IF v_room.result IS NULL OR v_room.max_rounds IS NULL THEN RAISE EXCEPTION 'Only completed Best-of matches can be finalized' USING ERRCODE='55000'; END IF;
    v_target:=floor(v_room.max_rounds::numeric/2)::integer+1;
    IF v_top<v_target AND v_room.round_number<v_room.max_rounds THEN RAISE EXCEPTION 'Match is still in progress' USING ERRCODE='55000'; END IF;
  END IF;

  v_player_ids:=array_remove(ARRAY[v_room.p1_player_id,v_room.p2_player_id,v_room.p3_player_id]::uuid[],NULL);
  IF cardinality(v_player_ids)<>v_room.max_players THEN
    RAISE EXCEPTION 'Room participant set is incomplete' USING ERRCODE='55000';
  END IF;
  IF EXISTS (
    SELECT 1 FROM unnest(v_player_ids) AS ids(id)
    LEFT JOIN public.rps_players p ON p.id=ids.id
    WHERE p.id IS NULL OR p.auth_user_id IS NULL
  ) THEN
    RAISE EXCEPTION 'Every match seat must be Auth-backed before rewards can be finalized' USING ERRCODE='55000';
  END IF;

  IF v_top>0 THEN
    IF v_room.p1_score=v_top THEN v_winners:=array_append(v_winners,v_room.p1_player_id); END IF;
    IF v_room.p2_score=v_top THEN v_winners:=array_append(v_winners,v_room.p2_player_id); END IF;
    IF v_room.p3_player_id IS NOT NULL AND v_room.p3_score=v_top THEN v_winners:=array_append(v_winners,v_room.p3_player_id); END IF;
  END IF;
  SELECT coalesce(array_agg(id::text ORDER BY id),ARRAY[]::text[])
    INTO v_match_winner_ids FROM unnest(v_winners) AS w(id);

  -- Acquire profile locks in stable order before reward/history mutations.
  PERFORM 1 FROM public.rps_players WHERE id=ANY(v_player_ids) ORDER BY id FOR UPDATE;

  UPDATE public.rps_rooms SET status='closed',match_finished_at=v_finished_at,
    match_winner_ids=v_match_winner_ids
  WHERE id=v_room.id;

  FOR v_participant IN
    SELECT p.id,p.username
    FROM public.rps_players p
    WHERE p.id=ANY(v_player_ids)
    ORDER BY p.id
  LOOP
    v_outcome:=CASE WHEN cardinality(v_winners)=0 THEN 'draw'
                    WHEN v_participant.id=ANY(v_winners) THEN 'win' ELSE 'loss' END;
    SELECT string_agg(op.username,', ' ORDER BY op.username)
      INTO v_opponents
    FROM public.rps_players op
    WHERE op.id=ANY(v_player_ids) AND op.id<>v_participant.id;

    INSERT INTO public.rps_match_history(room_id,player_id,opponent_name,outcome,mode)
    VALUES (v_room.id,v_participant.id,coalesce(v_opponents,'opponent'),v_outcome,
            coalesce(v_room.mode,'unlimited'))
    ON CONFLICT (room_id,player_id) DO NOTHING;
    GET DIAGNOSTICS v_rows=ROW_COUNT;
    IF v_rows=1 THEN
      v_xp:=CASE v_outcome WHEN 'win' THEN 100 WHEN 'loss' THEN 10 ELSE 25 END;
      v_coins:=CASE v_outcome WHEN 'win' THEN 50 WHEN 'loss' THEN 5 ELSE 10 END;
      UPDATE public.rps_players SET
        wins=wins+CASE WHEN v_outcome='win' THEN 1 ELSE 0 END,
        losses=losses+CASE WHEN v_outcome='loss' THEN 1 ELSE 0 END,
        draws=draws+CASE WHEN v_outcome='draw' THEN 1 ELSE 0 END,
        xp=xp+v_xp,coins=coins+v_coins,
        level=floor((xp+v_xp)::numeric/500)::integer+1,
        current_streak=CASE WHEN v_outcome='win' THEN current_streak+1 ELSE 0 END,
        best_streak=CASE WHEN v_outcome='win' THEN greatest(best_streak,current_streak+1) ELSE best_streak END
      WHERE id=v_participant.id AND auth_user_id IS NOT NULL;
    END IF;
  END LOOP;

  RETURN jsonb_build_object('finished',true,'already_finished',false,
    'match_finished_at',v_finished_at,'winner_count',cardinality(v_winners),
    'winner_ids',v_match_winner_ids);
END;
$function$;

-- Idempotent daily free-play reward derived entirely from the Auth session/date.
CREATE OR REPLACE FUNCTION public.rps_v2_claim_daily_login_reward()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_player public.rps_players%ROWTYPE;
  v_today date := current_date;
  v_rows integer;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Authentication required' USING ERRCODE='28000'; END IF;
  SELECT * INTO v_player FROM public.rps_players WHERE auth_user_id=v_uid FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Profile not found' USING ERRCODE='P0002'; END IF;
  INSERT INTO public.rps_share_rewards(player_id,reward_date,reward)
  VALUES(v_player.id,v_today,100)
  ON CONFLICT(player_id,reward_date) DO NOTHING;
  GET DIAGNOSTICS v_rows=ROW_COUNT;
  IF v_rows=0 THEN
    RETURN jsonb_build_object('claimed',false,'already_claimed',true,
                              'coins',v_player.coins,'reward_date',v_today);
  END IF;
  UPDATE public.rps_players SET coins=coins+100,updated_at=now()
    WHERE id=v_player.id RETURNING * INTO v_player;
  RETURN jsonb_build_object('claimed',true,'already_claimed',false,
    'reward',100,'coins',v_player.coins,'reward_date',v_today);
END;
$function$;

-- Participant-only room chat read. The v2 client receives only recent message fields.
CREATE OR REPLACE FUNCTION public.rps_v2_get_room_chat(
  p_room_id uuid,
  p_after timestamp with time zone DEFAULT NULL,
  p_limit integer DEFAULT 50
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_player public.rps_players%ROWTYPE;
  v_room public.rps_rooms%ROWTYPE;
  v_messages jsonb;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Authentication required' USING ERRCODE='28000'; END IF;
  IF p_limit IS NULL OR p_limit NOT BETWEEN 1 AND 50 THEN RAISE EXCEPTION 'Invalid page size' USING ERRCODE='22023'; END IF;
  SELECT * INTO v_player FROM public.rps_players WHERE auth_user_id=v_uid;
  IF NOT FOUND THEN RAISE EXCEPTION 'Profile not found' USING ERRCODE='P0002'; END IF;
  SELECT * INTO v_room FROM public.rps_rooms WHERE id=p_room_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Room not found' USING ERRCODE='P0002'; END IF;
  IF NOT (v_player.id = ANY(array_remove(ARRAY[v_room.p1_player_id,v_room.p2_player_id,v_room.p3_player_id]::uuid[],NULL))) THEN
    RAISE EXCEPTION 'Not a room participant' USING ERRCODE='42501';
  END IF;
  SELECT coalesce(jsonb_agg(jsonb_build_object('id',m.id,'player_name',m.player_name,
      'message',m.message,'created_at',m.created_at) ORDER BY m.created_at,m.id),'[]'::jsonb)
    INTO v_messages
  FROM (
    SELECT id,player_name,message,created_at
    FROM public.rps_room_messages
    WHERE room_id=p_room_id AND (p_after IS NULL OR created_at>p_after)
    ORDER BY created_at DESC,id DESC LIMIT p_limit
  ) AS m;
  RETURN v_messages;
END;
$function$;

-- Participant-only chat send; the server sets both sender ID and display name.
CREATE OR REPLACE FUNCTION public.rps_v2_send_room_chat(p_room_id uuid,p_message text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_player public.rps_players%ROWTYPE;
  v_room public.rps_rooms%ROWTYPE;
  v_message text := btrim(coalesce(p_message,''));
  v_id uuid;
  v_created timestamptz;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Authentication required' USING ERRCODE='28000'; END IF;
  IF char_length(v_message)<1 OR char_length(v_message)>240 OR v_message ~ '[[:cntrl:]]' THEN
    RAISE EXCEPTION 'Invalid message' USING ERRCODE='22023';
  END IF;
  SELECT * INTO v_player FROM public.rps_players WHERE auth_user_id=v_uid;
  IF NOT FOUND THEN RAISE EXCEPTION 'Profile not found' USING ERRCODE='P0002'; END IF;
  SELECT * INTO v_room FROM public.rps_rooms WHERE id=p_room_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Room not found' USING ERRCODE='P0002'; END IF;
  IF NOT (v_player.id = ANY(array_remove(ARRAY[v_room.p1_player_id,v_room.p2_player_id,v_room.p3_player_id]::uuid[],NULL))) THEN
    RAISE EXCEPTION 'Not a room participant' USING ERRCODE='42501';
  END IF;
  INSERT INTO public.rps_room_messages(room_id,player_id,player_name,message)
  VALUES(p_room_id,v_player.id,v_player.username,v_message)
  RETURNING id,created_at INTO v_id,v_created;
  RETURN jsonb_build_object('id',v_id,'player_name',v_player.username,
                            'message',v_message,'created_at',v_created);
END;
$function$;


-- Return only the caller's own profile; unlike a username lookup, this cannot recover another user's token or identity.
CREATE OR REPLACE FUNCTION public.rps_v2_get_my_profile()
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = pg_catalog, public AS $function$
DECLARE v_uid uuid := auth.uid(); v_player public.rps_players%ROWTYPE;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Authentication required' USING ERRCODE='28000'; END IF;
  SELECT * INTO v_player FROM public.rps_players WHERE auth_user_id=v_uid;
  IF NOT FOUND THEN RETURN NULL; END IF;
  RETURN jsonb_build_object('player_id',v_player.id,'username',v_player.username,'avatar',v_player.avatar,'avatar_key',v_player.avatar_key,'username_changed_at',v_player.username_changed_at,
    'coins',v_player.coins,'xp',v_player.xp,'level',v_player.level,'wins',v_player.wins,'losses',v_player.losses,
    'draws',v_player.draws,'current_streak',v_player.current_streak,'best_streak',v_player.best_streak);
END;
$function$;

-- Profile changes are scoped to auth.uid() and validated server-side.
CREATE OR REPLACE FUNCTION public.rps_v2_update_profile(p_username text,p_avatar text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public AS $function$
DECLARE v_uid uuid := auth.uid(); v_player public.rps_players%ROWTYPE; v_name text := btrim(coalesce(p_username,'')); v_avatar text := coalesce(p_avatar,'🦊');
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Authentication required' USING ERRCODE='28000'; END IF;
  IF char_length(v_name)<1 OR char_length(v_name)>24 OR v_name !~ '^[A-Za-z0-9 _.-]+$' THEN RAISE EXCEPTION 'Invalid display name' USING ERRCODE='22023'; END IF;
  IF v_avatar NOT IN ('🦊','🐼','🐸','🐯','🐙') THEN RAISE EXCEPTION 'Invalid avatar' USING ERRCODE='22023'; END IF;
  SELECT * INTO v_player FROM public.rps_players WHERE auth_user_id=v_uid FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Profile not found' USING ERRCODE='P0002'; END IF;
  IF v_name<>v_player.username AND v_player.username_changed_at IS NOT NULL AND v_player.username_changed_at>now()-interval '60 days' THEN RAISE EXCEPTION 'Username can only be changed every 60 days' USING ERRCODE='55000'; END IF;
  IF lower(v_name)<>lower(v_player.username) AND EXISTS (
    SELECT 1 FROM public.rps_players WHERE lower(username)=lower(v_name) AND id<>v_player.id
  ) THEN RAISE EXCEPTION 'Username is already in use' USING ERRCODE='23505'; END IF;
  UPDATE public.rps_players SET username=v_name,avatar=v_avatar,username_changed_at=CASE WHEN v_name<>v_player.username THEN now() ELSE username_changed_at END,updated_at=now()
    WHERE id=v_player.id RETURNING * INTO v_player;
  RETURN jsonb_build_object('player_id',v_player.id,'username',v_player.username,'avatar',v_player.avatar,'avatar_key',v_player.avatar_key,'username_changed_at',v_player.username_changed_at,
    'coins',v_player.coins,'xp',v_player.xp,'level',v_player.level,'wins',v_player.wins,'losses',v_player.losses,
    'draws',v_player.draws,'current_streak',v_player.current_streak,'best_streak',v_player.best_streak);
END;
$function$;

-- Personal match history is visible only to the authenticated profile owner.
CREATE OR REPLACE FUNCTION public.rps_v2_get_my_history(p_limit integer DEFAULT 8)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = pg_catalog, public AS $function$
DECLARE v_uid uuid := auth.uid(); v_player_id uuid; v_rows jsonb;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Authentication required' USING ERRCODE='28000'; END IF;
  SELECT id INTO v_player_id FROM public.rps_players WHERE auth_user_id=v_uid;
  IF v_player_id IS NULL THEN RAISE EXCEPTION 'Profile not found' USING ERRCODE='P0002'; END IF;
  IF p_limit IS NULL OR p_limit NOT BETWEEN 1 AND 20 THEN RAISE EXCEPTION 'Invalid page size' USING ERRCODE='22023'; END IF;
  SELECT coalesce(jsonb_agg(jsonb_build_object('opponent_name',h.opponent_name,'outcome',h.outcome,'mode',h.mode,'played_at',h.played_at) ORDER BY h.played_at DESC),'[]'::jsonb) INTO v_rows
  FROM (SELECT opponent_name,outcome,mode,played_at FROM public.rps_match_history WHERE player_id=v_player_id ORDER BY played_at DESC LIMIT p_limit) h;
  RETURN v_rows;
END;
$function$;

-- Anonymous leaderboard access is allowlisted to display names and aggregate ranking fields only.
CREATE OR REPLACE FUNCTION public.rps_v2_get_leaderboard(p_limit integer DEFAULT 10)
RETURNS TABLE (username text, avatar_key text, wins integer, losses integer, draws integer, level integer, xp integer)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $function$
  SELECT p.username,p.avatar_key,p.wins,p.losses,p.draws,p.level,p.xp
  FROM public.rps_players p
  ORDER BY p.wins DESC,p.xp DESC,p.created_at ASC,p.username ASC
  LIMIT LEAST(GREATEST(COALESCE(p_limit,10),1),50);
$function$;

-- Replace guest-token permissions and broad direct table access with RPC-only access.
DO $lockdown$
DECLARE t text; pol record;
BEGIN
  FOREACH t IN ARRAY ARRAY['rps_players','rps_rooms','rps_match_history','rps_messages','rps_room_messages','rps_share_rewards','rps_matches','rps_achievements'] LOOP
    IF to_regclass('public.'||t) IS NOT NULL THEN
      EXECUTE format('REVOKE ALL PRIVILEGES ON TABLE public.%I FROM PUBLIC, anon, authenticated',t);
      EXECUTE format('ALTER TABLE public.%I ENABLE ROW LEVEL SECURITY',t);
      FOR pol IN SELECT policyname FROM pg_policies WHERE schemaname='public' AND tablename=t LOOP
        EXECUTE format('DROP POLICY %I ON public.%I',pol.policyname,t);
      END LOOP;
    END IF;
  END LOOP;
END;
$lockdown$;

-- Guest-ID RPCs must not remain an alternate write path after cutover.
DO $revoke_legacy$
DECLARE f record;
BEGIN
  FOR f IN SELECT p.oid::regprocedure AS signature FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname='public' AND p.proname IN ('rps_join_room','rps_finalize_match','rps_claim_daily_login_reward')
  LOOP EXECUTE 'REVOKE ALL ON FUNCTION '||f.signature||' FROM PUBLIC, anon, authenticated'; END LOOP;
END;
$revoke_legacy$;

REVOKE ALL ON FUNCTION public.rps_v2_get_or_create_profile(text,text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.rps_v2_create_room(smallint,text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.rps_v2_join_room(text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.rps_v2_get_room_state(uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.rps_v2_submit_move(uuid,text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.rps_v2_advance_round(uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.rps_v2_finalize_match(uuid,boolean) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.rps_v2_claim_daily_login_reward() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.rps_v2_get_room_chat(uuid,timestamp with time zone,integer) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.rps_v2_send_room_chat(uuid,text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.rps_v2_get_my_history(integer) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.rps_v2_get_my_profile() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.rps_v2_update_profile(text,text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.rps_v2_get_or_create_profile(text,text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.rps_v2_create_room(smallint,text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.rps_v2_join_room(text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.rps_v2_get_room_state(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.rps_v2_submit_move(uuid,text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.rps_v2_advance_round(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.rps_v2_finalize_match(uuid,boolean) TO authenticated;
GRANT EXECUTE ON FUNCTION public.rps_v2_claim_daily_login_reward() TO authenticated;
GRANT EXECUTE ON FUNCTION public.rps_v2_get_room_chat(uuid,timestamp with time zone,integer) TO authenticated;
GRANT EXECUTE ON FUNCTION public.rps_v2_send_room_chat(uuid,text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.rps_v2_get_my_history(integer) TO authenticated;
GRANT EXECUTE ON FUNCTION public.rps_v2_get_my_profile() TO authenticated;
GRANT EXECUTE ON FUNCTION public.rps_v2_update_profile(text,text) TO authenticated;
REVOKE ALL ON FUNCTION public.rps_v2_get_leaderboard(integer) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.rps_v2_get_leaderboard(integer) TO anon, authenticated;
NOTIFY pgrst, 'reload schema';
COMMIT;

