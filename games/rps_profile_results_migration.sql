-- Finalize multiplayer rooms once, then persist match outcomes to guest profiles.
-- Bot rounds intentionally remain local and never enter the multiplayer leaderboard.

ALTER TABLE public.rps_rooms
  ADD COLUMN IF NOT EXISTS match_finished_at timestamptz,
  ADD COLUMN IF NOT EXISTS match_winner_ids text[] NOT NULL DEFAULT ARRAY[]::text[];

CREATE OR REPLACE FUNCTION public.rps_finalize_match(
  p_room_id uuid,
  p_guest_id text,
  p_force boolean DEFAULT false
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_room public.rps_rooms%ROWTYPE;
  v_top_score integer;
  v_target integer;
  v_completed_rounds integer;
  v_winners text[] := ARRAY[]::text[];
  v_player record;
  v_opponents text;
  v_outcome text;
  v_rows integer;
  v_xp_reward integer;
  v_coin_reward integer;
  v_finished_at timestamptz := now();
BEGIN
  SELECT * INTO v_room
  FROM public.rps_rooms
  WHERE id = p_room_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Room not found';
  END IF;

  IF p_guest_id IS NULL
     OR NOT (p_guest_id = ANY(array_remove(ARRAY[v_room.p1_id, v_room.p2_id, v_room.p3_id], NULL))) THEN
    RAISE EXCEPTION 'You are not a player in this room';
  END IF;

  IF v_room.match_finished_at IS NOT NULL THEN
    RETURN jsonb_build_object(
      'finished', true,
      'already_finished', true,
      'winner_ids', v_room.match_winner_ids,
      'match_finished_at', v_room.match_finished_at
    );
  END IF;

  v_completed_rounds := CASE
    WHEN v_room.result IS NOT NULL THEN v_room.round_number
    ELSE greatest(v_room.round_number - 1, 0)
  END;

  v_top_score := greatest(
    CASE WHEN v_room.p1_id IS NOT NULL THEN coalesce(v_room.p1_score,0) ELSE -1 END,
    CASE WHEN v_room.p2_id IS NOT NULL THEN coalesce(v_room.p2_score,0) ELSE -1 END,
    CASE WHEN v_room.p3_id IS NOT NULL THEN coalesce(v_room.p3_score,0) ELSE -1 END
  );

  -- Best-of-3/5/10 ends at a majority. If all rounds are used first,
  -- the top score wins; tied top scores are shared wins.
  IF NOT p_force THEN
    IF v_room.max_rounds IS NULL THEN
      RETURN jsonb_build_object('finished', false, 'reason', 'unlimited_match');
    END IF;
    IF v_room.result IS NULL THEN
      RETURN jsonb_build_object('finished', false, 'reason', 'round_not_complete');
    END IF;
    v_target := ceil(v_room.max_rounds::numeric / 2)::integer;
    IF v_top_score < v_target AND v_room.round_number < v_room.max_rounds THEN
      RETURN jsonb_build_object('finished', false, 'reason', 'match_in_progress');
    END IF;
  END IF;

  -- No completed round: close the empty room without creating a fake result.
  IF v_completed_rounds > 0 AND v_top_score > 0 THEN
    IF v_room.p1_id IS NOT NULL AND coalesce(v_room.p1_score,0) = v_top_score THEN
      v_winners := array_append(v_winners, v_room.p1_id);
    END IF;
    IF v_room.p2_id IS NOT NULL AND coalesce(v_room.p2_score,0) = v_top_score THEN
      v_winners := array_append(v_winners, v_room.p2_id);
    END IF;
    IF v_room.p3_id IS NOT NULL AND coalesce(v_room.p3_score,0) = v_top_score THEN
      v_winners := array_append(v_winners, v_room.p3_id);
    END IF;
  END IF;

  UPDATE public.rps_rooms
  SET status = 'closed',
      match_finished_at = v_finished_at,
      match_winner_ids = v_winners
  WHERE id = v_room.id;

  -- Profile counters and history are committed together and only once per room.
  FOR v_player IN
    SELECT seat.guest_id, seat.player_id, seat.player_name, seat.score
    FROM (VALUES
      (v_room.p1_id, v_room.p1_player_id, v_room.p1_name, coalesce(v_room.p1_score,0)),
      (v_room.p2_id, v_room.p2_player_id, v_room.p2_name, coalesce(v_room.p2_score,0)),
      (v_room.p3_id, v_room.p3_player_id, v_room.p3_name, coalesce(v_room.p3_score,0))
    ) AS seat(guest_id, player_id, player_name, score)
    WHERE seat.guest_id IS NOT NULL AND seat.player_id IS NOT NULL
  LOOP
    IF cardinality(v_winners) = 0 THEN
      v_outcome := 'draw';
    ELSIF v_player.guest_id = ANY(v_winners) THEN
      v_outcome := 'win';
    ELSE
      v_outcome := 'loss';
    END IF;

    SELECT string_agg(seat.player_name, ', ' ORDER BY seat.player_name)
      INTO v_opponents
    FROM (VALUES
      (v_room.p1_id, v_room.p1_name),
      (v_room.p2_id, v_room.p2_name),
      (v_room.p3_id, v_room.p3_name)
    ) AS seat(guest_id, player_name)
    WHERE seat.guest_id IS NOT NULL
      AND seat.guest_id <> v_player.guest_id;

    INSERT INTO public.rps_match_history(room_id, player_id, opponent_name, outcome, mode)
    VALUES (v_room.id, v_player.player_id, coalesce(v_opponents, 'opponent'), v_outcome, coalesce(v_room.mode,'unlimited'))
    ON CONFLICT (room_id, player_id) DO NOTHING;

    GET DIAGNOSTICS v_rows = ROW_COUNT;
    IF v_rows = 1 THEN
      v_xp_reward := CASE v_outcome WHEN 'win' THEN 100 WHEN 'loss' THEN 10 ELSE 25 END;
      v_coin_reward := CASE v_outcome WHEN 'win' THEN 50 WHEN 'loss' THEN 5 ELSE 10 END;
      UPDATE public.rps_players
      SET wins = wins + CASE WHEN v_outcome = 'win' THEN 1 ELSE 0 END,
          losses = losses + CASE WHEN v_outcome = 'loss' THEN 1 ELSE 0 END,
          draws = draws + CASE WHEN v_outcome = 'draw' THEN 1 ELSE 0 END,
          xp = xp + v_xp_reward,
          coins = coins + v_coin_reward,
          level = floor((xp + v_xp_reward)::numeric / 500)::integer + 1,
          current_streak = CASE WHEN v_outcome = 'win' THEN current_streak + 1 ELSE 0 END,
          best_streak = CASE WHEN v_outcome = 'win' THEN greatest(best_streak, current_streak + 1) ELSE best_streak END
      WHERE id = v_player.player_id;
    END IF;
  END LOOP;

  RETURN jsonb_build_object(
    'finished', true,
    'already_finished', false,
    'winner_ids', v_winners,
    'match_finished_at', v_finished_at,
    'completed_rounds', v_completed_rounds
  );
END;
$$;

REVOKE ALL ON FUNCTION public.rps_finalize_match(uuid,text,boolean) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.rps_finalize_match(uuid,text,boolean) TO anon, authenticated;
NOTIFY pgrst, 'reload schema';
