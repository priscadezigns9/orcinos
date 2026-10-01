-- Enforce Best-of 3/5 for new rooms and cap legacy NULL/unlimited rooms at five rounds.
-- No existing room rows are updated, cancelled, or exposed by this migration.
BEGIN;

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
  IF p_mode IS NULL OR p_mode NOT IN ('best3','best5') THEN
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

  v_max_rounds := CASE p_mode WHEN 'best3' THEN 3 ELSE 5 END;

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
  IF true THEN
    v_target:=floor(coalesce(v_room.max_rounds,5)::numeric/2)::integer+1;
    v_top:=greatest(v_room.p1_score,v_room.p2_score,v_room.p3_score);
    IF v_top>=v_target OR v_room.round_number>=coalesce(v_room.max_rounds,5) THEN
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
    IF v_room.result IS NULL THEN RAISE EXCEPTION 'Only completed matches can be finalized' USING ERRCODE='55000'; END IF;
    v_target:=floor(coalesce(v_room.max_rounds,5)::numeric/2)::integer+1;
    IF v_top<v_target AND v_room.round_number<coalesce(v_room.max_rounds,5) THEN RAISE EXCEPTION 'Match is still in progress' USING ERRCODE='55000'; END IF;
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

REVOKE ALL ON FUNCTION public.rps_v2_create_room(smallint,text,integer) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.rps_v2_create_room(smallint,text,integer) TO authenticated;
REVOKE ALL ON FUNCTION public.rps_v2_advance_round(uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.rps_v2_advance_round(uuid) TO authenticated;
REVOKE ALL ON FUNCTION public.rps_v2_finalize_match(uuid,boolean) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.rps_v2_finalize_match(uuid,boolean) TO authenticated;
INSERT INTO supabase_migrations.schema_migrations (version,name,created_by)
VALUES ('20261001100000','rps_match_round_caps_20261001','zapia') ON CONFLICT DO NOTHING;
NOTIFY pgrst,'reload schema';
COMMIT;
