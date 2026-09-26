-- Add 3-player private rooms while preserving 1v1 rooms.
-- Multiplayer rounds: if exactly two gestures are present, every player
-- using the winning gesture wins that round. All-same or all-three gestures draw.

ALTER TABLE public.rps_rooms
  ADD COLUMN IF NOT EXISTS max_players smallint NOT NULL DEFAULT 2,
  ADD COLUMN IF NOT EXISTS p3_id text,
  ADD COLUMN IF NOT EXISTS p3_name text,
  ADD COLUMN IF NOT EXISTS p3_player_id uuid REFERENCES public.rps_players(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS p3_move text,
  ADD COLUMN IF NOT EXISTS p3_score integer NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS winner_ids text[] NOT NULL DEFAULT ARRAY[]::text[];

ALTER TABLE public.rps_rooms
  DROP CONSTRAINT IF EXISTS rps_rooms_p3_move_check,
  ADD CONSTRAINT rps_rooms_p3_move_check
    CHECK (p3_move IS NULL OR p3_move IN ('rock','paper','scissors'));

ALTER TABLE public.rps_rooms
  DROP CONSTRAINT IF EXISTS rps_rooms_max_players_check,
  ADD CONSTRAINT rps_rooms_max_players_check CHECK (max_players IN (2,3));

ALTER TABLE public.rps_rooms
  DROP CONSTRAINT IF EXISTS rps_rooms_result_check,
  ADD CONSTRAINT rps_rooms_result_check
    CHECK (result IS NULL OR result IN ('p1','p2','p3','multi','draw'));

CREATE INDEX IF NOT EXISTS rps_rooms_waiting_capacity
  ON public.rps_rooms(room_code, status, max_players);

-- Atomically assign the next available seat so simultaneous joins cannot
-- overwrite each other. A 3-player room stays waiting until seat 3 is filled.
CREATE OR REPLACE FUNCTION public.rps_join_room(
  p_room_code text,
  p_guest_id text,
  p_player_id uuid,
  p_player_name text
)
RETURNS TABLE(room_id uuid, player_slot smallint, room_status text, max_players smallint)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_room public.rps_rooms%ROWTYPE;
  v_slot smallint;
  v_status text;
BEGIN
  IF coalesce(length(btrim(p_guest_id)), 0) = 0
     OR coalesce(length(btrim(p_player_name)), 0) = 0
     OR p_player_id IS NULL THEN
    RAISE EXCEPTION 'A player profile and username are required';
  END IF;

  SELECT * INTO v_room
  FROM public.rps_rooms
  WHERE room_code = upper(btrim(p_room_code))
    AND status = 'waiting'
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Room is not accepting players';
  END IF;

  IF v_room.p1_id = p_guest_id THEN
    v_slot := 1;
  ELSIF v_room.p2_id = p_guest_id THEN
    v_slot := 2;
  ELSIF v_room.p3_id = p_guest_id THEN
    v_slot := 3;
  ELSIF v_room.p2_id IS NULL THEN
    v_slot := 2;
  ELSIF v_room.max_players >= 3 AND v_room.p3_id IS NULL THEN
    v_slot := 3;
  ELSE
    RAISE EXCEPTION 'Room is full';
  END IF;

  IF v_slot = 2 AND v_room.p2_id IS NULL THEN
    v_status := CASE WHEN v_room.max_players = 2 OR v_room.p3_id IS NOT NULL THEN 'playing' ELSE 'waiting' END;
    UPDATE public.rps_rooms
      SET p2_id = p_guest_id,
          p2_name = btrim(p_player_name),
          p2_player_id = p_player_id,
          status = v_status
      WHERE id = v_room.id;
  ELSIF v_slot = 3 AND v_room.p3_id IS NULL THEN
    v_status := 'playing';
    UPDATE public.rps_rooms
      SET p3_id = p_guest_id,
          p3_name = btrim(p_player_name),
          p3_player_id = p_player_id,
          status = v_status
      WHERE id = v_room.id;
  ELSE
    v_status := v_room.status;
  END IF;

  RETURN QUERY SELECT v_room.id, v_slot, v_status, v_room.max_players;
END;
$$;

REVOKE ALL ON FUNCTION public.rps_join_room(text,text,uuid,text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.rps_join_room(text,text,uuid,text) TO anon, authenticated;
NOTIFY pgrst, 'reload schema';
