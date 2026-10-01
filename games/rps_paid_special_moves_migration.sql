-- PvP-only paid Hammer and Reveal Hand actions.
BEGIN;

ALTER TABLE public.rps_rooms DROP CONSTRAINT IF EXISTS rps_rooms_p1_move_check;
ALTER TABLE public.rps_rooms ADD CONSTRAINT rps_rooms_p1_move_check
  CHECK (p1_move IS NULL OR p1_move IN ('rock','paper','scissors','hammer'));
ALTER TABLE public.rps_rooms DROP CONSTRAINT IF EXISTS rps_rooms_p2_move_check;
ALTER TABLE public.rps_rooms ADD CONSTRAINT rps_rooms_p2_move_check
  CHECK (p2_move IS NULL OR p2_move IN ('rock','paper','scissors','hammer'));
ALTER TABLE public.rps_rooms DROP CONSTRAINT IF EXISTS rps_rooms_p3_move_check;
ALTER TABLE public.rps_rooms ADD CONSTRAINT rps_rooms_p3_move_check
  CHECK (p3_move IS NULL OR p3_move IN ('rock','paper','scissors','hammer'));

CREATE TABLE IF NOT EXISTS public.rps_special_move_uses (
  room_id uuid NOT NULL REFERENCES public.rps_rooms(id) ON DELETE CASCADE,
  player_id uuid NOT NULL REFERENCES public.rps_players(id) ON DELETE CASCADE,
  round_number integer NOT NULL,
  special text NOT NULL CHECK (special IN ('hammer','reveal_hand')),
  cost integer NOT NULL CHECK (cost>0),
  revealed_moves jsonb,
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (room_id,round_number,player_id)
);
CREATE INDEX IF NOT EXISTS rps_special_reveal_match_lookup_idx
  ON public.rps_special_move_uses(room_id,player_id) WHERE special='reveal_hand';
ALTER TABLE public.rps_special_move_uses ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.rps_special_move_uses FROM PUBLIC,anon,authenticated;

CREATE OR REPLACE FUNCTION public.rps_v2_get_room_state(p_room_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
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
    'stake',coalesce(v_room.stake,0),'pot',coalesce(v_room.stake,0)*v_room.max_players,
    'stake_outcome',coalesce(v_room.stake_outcome,'none'),
    'stake_payout',coalesce(v_room.stake_payout,0),
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
    'my_slot',v_slot,'players',v_players,
    'my_special_used_this_round',EXISTS (
      SELECT 1 FROM public.rps_special_move_uses u
      WHERE u.room_id=v_room.id AND u.player_id=v_player.id AND u.round_number=v_room.round_number
    ),
    'my_reveal_hand_used',EXISTS (
      SELECT 1 FROM public.rps_special_move_uses u
      WHERE u.room_id=v_room.id AND u.player_id=v_player.id AND u.special='reveal_hand'
    ),
    'match_finished',(v_room.match_finished_at IS NOT NULL),
    'match_finished_at',v_room.match_finished_at,'match_winner_ids',v_room.match_winner_ids
  );
END;
$function$;

CREATE OR REPLACE FUNCTION public.rps_v2_submit_move(p_room_id uuid, p_move text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
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
  v_has_hammer boolean;
  v_rows integer;
  v_winning_move text;
  v_winners uuid[] := ARRAY[]::uuid[];
  v_result text;
  v_current_round integer;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Authentication required' USING ERRCODE='28000'; END IF;
  IF p_move IS NULL OR p_move NOT IN ('rock','paper','scissors','hammer') THEN RAISE EXCEPTION 'Invalid move' USING ERRCODE='22023'; END IF;
  SELECT * INTO v_player FROM public.rps_players WHERE auth_user_id=v_uid FOR UPDATE;
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
    IF p_move='hammer' THEN
      IF EXISTS (SELECT 1 FROM public.rps_special_move_uses u
        WHERE u.room_id=v_room.id AND u.player_id=v_player.id AND u.round_number=v_room.round_number) THEN
        RAISE EXCEPTION 'Only one special move may be used per turn' USING ERRCODE='55000';
      END IF;
      IF v_player.coins < 300+coalesce(v_room.stake,0) THEN
        RAISE EXCEPTION 'Hammer costs 300 Chips, and you must keep enough Chips for your room stake' USING ERRCODE='P0001';
      END IF;
      UPDATE public.rps_players SET coins=coins-300,updated_at=now()
        WHERE id=v_player.id AND coins>=300+coalesce(v_room.stake,0);
      GET DIAGNOSTICS v_rows=ROW_COUNT;
      IF v_rows<>1 THEN RAISE EXCEPTION 'Not enough available RPS Chips for Hammer' USING ERRCODE='P0001'; END IF;
      INSERT INTO public.rps_special_move_uses(room_id,player_id,round_number,special,cost)
        VALUES(v_room.id,v_player.id,v_room.round_number,'hammer',300);
    END IF;
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
    SELECT bool_or(m='rock'),bool_or(m='paper'),bool_or(m='scissors'),bool_or(m='hammer')
      INTO v_has_rock,v_has_paper,v_has_scissors,v_has_hammer
    FROM (VALUES (v_room.p1_move),(v_room.p2_move),
          (CASE WHEN v_room.max_players=3 THEN v_room.p3_move ELSE NULL END)) AS moves(m)
    WHERE m IS NOT NULL;
    v_winning_move := CASE
      WHEN v_has_rock AND v_has_paper THEN 'paper'
      WHEN v_has_rock AND v_has_scissors THEN 'rock'
      WHEN v_has_paper AND v_has_scissors THEN 'scissors'
      WHEN v_has_rock AND v_has_hammer THEN 'rock'
      WHEN v_has_paper AND v_has_hammer THEN 'hammer'
      WHEN v_has_scissors AND v_has_hammer THEN 'hammer'
      ELSE NULL END;
    IF v_winning_move IS NULL THEN RAISE EXCEPTION 'Could not resolve this move pair' USING ERRCODE='22023'; END IF;
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
$function$
;

CREATE OR REPLACE FUNCTION public.rps_v2_reveal_hand(p_room_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog', 'public'
AS $function$
DECLARE
  v_uid uuid:=auth.uid();
  v_player public.rps_players%ROWTYPE;
  v_room public.rps_rooms%ROWTYPE;
  v_slot smallint;
  v_own_move text;
  v_revealed jsonb;
  v_existing jsonb;
  v_rows integer;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Authentication required' USING ERRCODE='28000'; END IF;
  SELECT * INTO v_player FROM public.rps_players WHERE auth_user_id=v_uid FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Profile not found' USING ERRCODE='P0002'; END IF;
  SELECT * INTO v_room FROM public.rps_rooms WHERE id=p_room_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Room not found' USING ERRCODE='P0002'; END IF;
  v_slot:=CASE WHEN v_room.p1_player_id=v_player.id THEN 1
               WHEN v_room.p2_player_id=v_player.id THEN 2
               WHEN v_room.p3_player_id=v_player.id THEN 3 ELSE NULL END;
  IF v_slot IS NULL THEN RAISE EXCEPTION 'Not a room participant' USING ERRCODE='42501'; END IF;

  -- A retry in the same round returns the exact same private reveal without another charge.
  SELECT u.revealed_moves INTO v_existing FROM public.rps_special_move_uses u
  WHERE u.room_id=v_room.id AND u.player_id=v_player.id
    AND u.round_number=v_room.round_number AND u.special='reveal_hand';
  IF FOUND THEN
    RETURN jsonb_build_object('revealed_moves',v_existing,'already_revealed',true,
      'coins_left',v_player.coins,'room_state',public.rps_v2_get_room_state(p_room_id));
  END IF;
  IF EXISTS (SELECT 1 FROM public.rps_special_move_uses u
    WHERE u.room_id=v_room.id AND u.player_id=v_player.id AND u.special='reveal_hand') THEN
    RAISE EXCEPTION 'Reveal Hand can only be used once per match' USING ERRCODE='55000';
  END IF;
  IF v_room.status<>'playing' OR v_room.result IS NOT NULL OR v_room.match_finished_at IS NOT NULL THEN
    RAISE EXCEPTION 'Reveal Hand is available only during an active turn' USING ERRCODE='55000';
  END IF;
  v_own_move:=CASE v_slot WHEN 1 THEN v_room.p1_move WHEN 2 THEN v_room.p2_move ELSE v_room.p3_move END;
  IF v_own_move IS NOT NULL THEN RAISE EXCEPTION 'Lock in Reveal Hand before choosing your move' USING ERRCODE='55000'; END IF;
  IF EXISTS (SELECT 1 FROM public.rps_special_move_uses u
    WHERE u.room_id=v_room.id AND u.player_id=v_player.id AND u.round_number=v_room.round_number) THEN
    RAISE EXCEPTION 'Only one special move may be used per turn' USING ERRCODE='55000';
  END IF;
  IF EXISTS (
    SELECT 1 FROM (VALUES
      (1::smallint,v_room.p1_player_id,v_room.p1_move),
      (2::smallint,v_room.p2_player_id,v_room.p2_move),
      (3::smallint,v_room.p3_player_id,v_room.p3_move)
    ) AS s(slot,player_id,move)
    WHERE s.player_id IS NOT NULL AND s.player_id<>v_player.id AND s.move IS NULL
  ) THEN
    RAISE EXCEPTION 'Wait until every opponent has locked in a move' USING ERRCODE='55000';
  END IF;
  IF v_player.coins < 500+coalesce(v_room.stake,0) THEN
    RAISE EXCEPTION 'Reveal Hand costs 500 Chips, and you must keep enough Chips for your room stake' USING ERRCODE='P0001';
  END IF;
  SELECT coalesce(jsonb_agg(jsonb_build_object('slot',s.slot,'name',s.display_name,'move',s.move) ORDER BY s.slot),'[]'::jsonb)
    INTO v_revealed
  FROM (VALUES
    (1::smallint,v_room.p1_player_id,v_room.p1_name,v_room.p1_move),
    (2::smallint,v_room.p2_player_id,v_room.p2_name,v_room.p2_move),
    (3::smallint,v_room.p3_player_id,v_room.p3_name,v_room.p3_move)
  ) AS s(slot,player_id,display_name,move)
  WHERE s.player_id IS NOT NULL AND s.player_id<>v_player.id;
  UPDATE public.rps_players SET coins=coins-500,updated_at=now()
    WHERE id=v_player.id AND coins>=500+coalesce(v_room.stake,0);
  GET DIAGNOSTICS v_rows=ROW_COUNT;
  IF v_rows<>1 THEN RAISE EXCEPTION 'Not enough available RPS Chips for Reveal Hand' USING ERRCODE='P0001'; END IF;
  INSERT INTO public.rps_special_move_uses(room_id,player_id,round_number,special,cost,revealed_moves)
    VALUES(v_room.id,v_player.id,v_room.round_number,'reveal_hand',500,v_revealed);
  SELECT coins INTO v_player.coins FROM public.rps_players WHERE id=v_player.id;
  RETURN jsonb_build_object('revealed_moves',v_revealed,'already_revealed',false,
    'coins_left',v_player.coins,'room_state',public.rps_v2_get_room_state(p_room_id));
END;
$function$;

REVOKE ALL ON FUNCTION public.rps_v2_submit_move(uuid,text) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.rps_v2_submit_move(uuid,text) TO authenticated;
REVOKE ALL ON FUNCTION public.rps_v2_reveal_hand(uuid) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.rps_v2_reveal_hand(uuid) TO authenticated;
REVOKE ALL ON FUNCTION public.rps_v2_get_room_state(uuid) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.rps_v2_get_room_state(uuid) TO authenticated;

INSERT INTO supabase_migrations.schema_migrations(version,name,created_by)
VALUES ('20260930215800','rps_paid_special_moves_20260930','zapia')
ON CONFLICT DO NOTHING;
NOTIFY pgrst,'reload schema';
COMMIT;
