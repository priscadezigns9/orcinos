-- PvP-only virtual RPS Chip wagers. No cash value or bot wagers.
BEGIN;

ALTER TABLE public.rps_rooms
  ADD COLUMN IF NOT EXISTS stake_outcome text NOT NULL DEFAULT 'none',
  ADD COLUMN IF NOT EXISTS stake_payout integer NOT NULL DEFAULT 0;

ALTER TABLE public.rps_rooms DROP CONSTRAINT IF EXISTS rps_rooms_stake_range_check;
ALTER TABLE public.rps_rooms ADD CONSTRAINT rps_rooms_stake_range_check
  CHECK (stake=0 OR stake BETWEEN 200 AND 1000);
ALTER TABLE public.rps_rooms DROP CONSTRAINT IF EXISTS rps_rooms_stake_outcome_check;
ALTER TABLE public.rps_rooms ADD CONSTRAINT rps_rooms_stake_outcome_check
  CHECK (stake_outcome IN ('none','won','refunded','cancelled'));
ALTER TABLE public.rps_rooms DROP CONSTRAINT IF EXISTS rps_rooms_stake_payout_check;
ALTER TABLE public.rps_rooms ADD CONSTRAINT rps_rooms_stake_payout_check CHECK (stake_payout>=0);

DROP FUNCTION IF EXISTS public.rps_v2_create_room(smallint,text);
DROP FUNCTION IF EXISTS public.rps_v2_join_room(text);

CREATE OR REPLACE FUNCTION public.rps_v2_create_room(p_max_players smallint, p_mode text, p_stake integer DEFAULT 0)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
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

  IF p_stake IS NULL THEN p_stake := 0; END IF;
  IF p_stake <> 0 AND p_stake NOT BETWEEN 200 AND 1000 THEN
    RAISE EXCEPTION 'Stake must be 0 or between 200 and 1000 RPS Chips' USING ERRCODE='22023';
  END IF;

  SELECT * INTO v_player
  FROM public.rps_players
  WHERE auth_user_id = v_uid
  FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Create/load a free-play profile first' USING ERRCODE='P0002';
  END IF;
  IF p_stake > 0 AND v_player.coins < p_stake THEN
    RAISE EXCEPTION 'You need at least % RPS Chips to create this wager room', p_stake USING ERRCODE='P0001';
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
        status, round_number, mode, max_rounds, stake
      ) VALUES (
        v_code, p_max_players, v_player.id::text, v_player.username, v_player.id,
        'waiting', 1, p_mode, v_max_rounds, p_stake
      ) RETURNING * INTO v_room;
      EXIT;
    EXCEPTION WHEN unique_violation THEN
      -- Retry only room-code collisions; all other constraints should surface.
      IF v_attempt >= 5 THEN RAISE; END IF;
    END;
  END LOOP;

  RETURN jsonb_build_object('room_id',v_room.id,'room_code',v_room.room_code,
    'status',v_room.status,'max_players',v_room.max_players,
    'stake',v_room.stake,'pot',v_room.stake*v_room.max_players);
END;
$function$;


CREATE OR REPLACE FUNCTION public.rps_v2_join_room(p_room_code text, p_accept_stake boolean DEFAULT false)
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
  v_already_seated boolean := false;
  v_player_ids uuid[];
  v_player_count integer;
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

  IF NOT v_already_seated AND v_room.stake>0 THEN
    IF NOT coalesce(p_accept_stake,false) THEN
      v_player_count := (CASE WHEN v_room.p1_player_id IS NULL THEN 0 ELSE 1 END)
                      + (CASE WHEN v_room.p2_player_id IS NULL THEN 0 ELSE 1 END)
                      + (CASE WHEN v_room.p3_player_id IS NULL THEN 0 ELSE 1 END);
      RETURN jsonb_build_object('confirmation_required',true,'stake',v_room.stake,
        'pot',v_room.stake*v_room.max_players,'max_players',v_room.max_players,
        'players_joined',v_player_count);
    END IF;
    IF v_player.coins < v_room.stake THEN
      RAISE EXCEPTION 'You need at least % RPS Chips to accept this room wager', v_room.stake USING ERRCODE='P0001';
    END IF;
  END IF;

  IF NOT v_already_seated AND v_slot=2 AND v_room.p2_player_id IS NULL THEN
    UPDATE public.rps_rooms SET p2_id=v_player.id::text, p2_name=v_player.username,
      p2_player_id=v_player.id,
      status=CASE WHEN v_room.max_players=2 THEN 'playing' ELSE 'waiting' END
    WHERE id=v_room.id;
  ELSIF NOT v_already_seated AND v_slot=3 AND v_room.p3_player_id IS NULL THEN
    UPDATE public.rps_rooms SET p3_id=v_player.id::text, p3_name=v_player.username,
      p3_player_id=v_player.id, status='playing'
    WHERE id=v_room.id;
  END IF;

  SELECT * INTO v_room FROM public.rps_rooms WHERE id=v_room.id FOR UPDATE;
  IF v_room.status='playing' AND v_room.stake>0 THEN
    v_player_ids:=array_remove(ARRAY[v_room.p1_player_id,v_room.p2_player_id,v_room.p3_player_id]::uuid[],NULL);
    IF cardinality(v_player_ids)<>v_room.max_players THEN
      RAISE EXCEPTION 'Wager room is missing a player seat' USING ERRCODE='55000';
    END IF;
    PERFORM 1 FROM public.rps_players WHERE id=ANY(v_player_ids) ORDER BY id FOR UPDATE;
    IF EXISTS (SELECT 1 FROM public.rps_players WHERE id=ANY(v_player_ids) AND coins<v_room.stake) THEN
      RAISE EXCEPTION 'Every player needs at least % RPS Chips for this wager', v_room.stake USING ERRCODE='P0001';
    END IF;
    IF EXISTS (
      SELECT 1 FROM public.rps_rooms r
      WHERE r.id<>v_room.id AND r.status='playing' AND r.stake>0 AND r.match_finished_at IS NULL
        AND (r.p1_player_id=ANY(v_player_ids) OR r.p2_player_id=ANY(v_player_ids) OR r.p3_player_id=ANY(v_player_ids))
    ) THEN
      RAISE EXCEPTION 'A player is already in another wagered match' USING ERRCODE='55000';
    END IF;
  END IF;

  RETURN jsonb_build_object('room_id',v_room.id,'room_code',v_room.room_code,
    'player_slot',v_slot,'status',v_room.status,'max_players',v_room.max_players,
    'stake',v_room.stake,'pot',v_room.stake*v_room.max_players);
END;
$function$;

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
    'my_slot',v_slot,'players',v_players,'match_finished',(v_room.match_finished_at IS NOT NULL),
    'match_finished_at',v_room.match_finished_at,'match_winner_ids',v_room.match_winner_ids
  );
END;
$function$;


CREATE OR REPLACE FUNCTION public.rps_v2_finalize_match(p_room_id uuid, p_allow_leave boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
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
  v_stake_outcome text := 'none';
  v_stake_payout integer := 0;
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
      'match_finished_at',v_room.match_finished_at,'stake_outcome',v_room.stake_outcome,
      'stake_payout',v_room.stake_payout);
  END IF;
  IF v_room.status<>'playing' THEN
    RAISE EXCEPTION 'Room is not active' USING ERRCODE='55000';
  END IF;
  v_completed_rounds:=CASE WHEN v_room.result IS NOT NULL THEN v_room.round_number ELSE greatest(v_room.round_number-1,0) END;
  v_top:=greatest(v_room.p1_score,v_room.p2_score,v_room.p3_score);
  IF v_completed_rounds=0 AND p_allow_leave THEN
    v_stake_outcome:=CASE WHEN v_room.stake>0 THEN 'cancelled' ELSE 'none' END;
    UPDATE public.rps_rooms SET status='closed',match_finished_at=now(),match_winner_ids=ARRAY[]::text[],
      stake_outcome=v_stake_outcome,stake_payout=0 WHERE id=v_room.id;
    RETURN jsonb_build_object('finished',true,'already_finished',false,'winner_count',0,
      'completed_rounds',0,'stake_outcome',v_stake_outcome,'stake_payout',0);
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

  -- Acquire profile locks in stable order before wager settlement and reward/history mutations.
  PERFORM 1 FROM public.rps_players WHERE id=ANY(v_player_ids) ORDER BY id FOR UPDATE;

  IF v_room.stake>0 THEN
    IF cardinality(v_winners)=1 THEN
      IF EXISTS (SELECT 1 FROM public.rps_players WHERE id=ANY(v_player_ids) AND coins<v_room.stake) THEN
        RAISE EXCEPTION 'A player no longer has enough RPS Chips to settle the wager' USING ERRCODE='P0001';
      END IF;
      v_stake_payout:=v_room.stake*cardinality(v_player_ids);
      v_stake_outcome:='won';
      UPDATE public.rps_players SET
        coins=coins-v_room.stake+CASE WHEN id=v_winners[1] THEN v_stake_payout ELSE 0 END,
        updated_at=now()
      WHERE id=ANY(v_player_ids) AND auth_user_id IS NOT NULL;
      GET DIAGNOSTICS v_rows=ROW_COUNT;
      IF v_rows<>cardinality(v_player_ids) THEN
        RAISE EXCEPTION 'Wager could not be settled for every player' USING ERRCODE='P0001';
      END IF;
    ELSE
      -- A draw or shared top score returns every player's stake; there is no sole winner.
      v_stake_outcome:='refunded';
      v_stake_payout:=0;
    END IF;
  END IF;

  UPDATE public.rps_rooms SET status='closed',match_finished_at=v_finished_at,
    match_winner_ids=v_match_winner_ids,stake_outcome=v_stake_outcome,stake_payout=v_stake_payout
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
    'winner_ids',v_match_winner_ids,'stake_outcome',v_stake_outcome,
    'stake_payout',v_stake_payout);
END;
$function$;


CREATE OR REPLACE FUNCTION public.rps_v2_leave_waiting_room(p_room_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog', 'public'
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_player public.rps_players%ROWTYPE;
  v_room public.rps_rooms%ROWTYPE;
  v_outcome text;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Authentication required' USING ERRCODE='28000'; END IF;
  SELECT * INTO v_player FROM public.rps_players WHERE auth_user_id=v_uid FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Profile not found' USING ERRCODE='P0002'; END IF;
  SELECT * INTO v_room FROM public.rps_rooms WHERE id=p_room_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Room not found' USING ERRCODE='P0002'; END IF;
  IF v_room.status<>'waiting' THEN RAISE EXCEPTION 'Only a waiting room can be left this way' USING ERRCODE='55000'; END IF;
  IF v_room.p1_player_id=v_player.id THEN
    v_outcome:=CASE WHEN v_room.stake>0 THEN 'cancelled' ELSE 'none' END;
    UPDATE public.rps_rooms SET status='closed',match_finished_at=now(),
      match_winner_ids=ARRAY[]::text[],stake_outcome=v_outcome,stake_payout=0
    WHERE id=v_room.id;
  ELSIF v_room.p2_player_id=v_player.id THEN
    UPDATE public.rps_rooms SET p2_id=NULL,p2_name=NULL,p2_player_id=NULL WHERE id=v_room.id;
  ELSIF v_room.p3_player_id=v_player.id THEN
    UPDATE public.rps_rooms SET p3_id=NULL,p3_name=NULL,p3_player_id=NULL WHERE id=v_room.id;
  ELSE
    RAISE EXCEPTION 'Not a room participant' USING ERRCODE='42501';
  END IF;
  RETURN jsonb_build_object('left',true,'status',CASE WHEN v_room.p1_player_id=v_player.id THEN 'closed' ELSE 'waiting' END);
END;
$function$;

REVOKE ALL ON FUNCTION public.rps_v2_create_room(smallint,text,integer) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.rps_v2_create_room(smallint,text,integer) TO authenticated;
REVOKE ALL ON FUNCTION public.rps_v2_join_room(text,boolean) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.rps_v2_join_room(text,boolean) TO authenticated;
REVOKE ALL ON FUNCTION public.rps_v2_leave_waiting_room(uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.rps_v2_leave_waiting_room(uuid) TO authenticated;
REVOKE ALL ON FUNCTION public.rps_v2_get_room_state(uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.rps_v2_get_room_state(uuid) TO authenticated;
REVOKE ALL ON FUNCTION public.rps_v2_finalize_match(uuid,boolean) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.rps_v2_finalize_match(uuid,boolean) TO authenticated;

INSERT INTO supabase_migrations.schema_migrations (version,name,created_by)
VALUES ('20260930210000','rps_pvp_coin_wagers_20260930','zapia')
ON CONFLICT DO NOTHING;
NOTIFY pgrst,'reload schema';
COMMIT;
