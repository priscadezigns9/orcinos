-- Open RPS tables are explicitly opt-in; legacy and ordinary private rooms stay private.
-- The public lobby exposes only minimal metadata and opaque room UUIDs through authenticated RPCs.
BEGIN;

ALTER TABLE public.rps_rooms
  ADD COLUMN IF NOT EXISTS visibility text NOT NULL DEFAULT 'private';

ALTER TABLE public.rps_rooms
  DROP CONSTRAINT IF EXISTS rps_rooms_visibility_check;
ALTER TABLE public.rps_rooms
  ADD CONSTRAINT rps_rooms_visibility_check
  CHECK (visibility IN ('private', 'open'));

CREATE INDEX IF NOT EXISTS rps_rooms_open_lobby_idx
  ON public.rps_rooms (stake, mode, max_players)
  WHERE visibility = 'open' AND status = 'waiting';

-- Create through the existing locked/authenticated private-room path, then mark only
-- the newly created host-owned row open. Do not return the generated room code.
CREATE OR REPLACE FUNCTION public.rps_v2_create_open_room(
  p_max_players smallint,
  p_mode text,
  p_stake integer DEFAULT 0
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog', 'public'
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_player public.rps_players%ROWTYPE;
  v_created jsonb;
  v_room public.rps_rooms%ROWTYPE;
  v_room_id uuid;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'Authentication required' USING ERRCODE='28000';
  END IF;
  IF p_max_players IS NULL OR p_max_players NOT IN (2, 3) THEN
    RAISE EXCEPTION 'Unsupported room capacity' USING ERRCODE='22023';
  END IF;
  IF p_mode IS NULL OR p_mode NOT IN ('best3', 'best5') THEN
    RAISE EXCEPTION 'Unsupported match mode' USING ERRCODE='22023';
  END IF;

  p_stake := COALESCE(p_stake, 0);
  IF p_stake <> 0 AND (p_stake < 200 OR p_stake > 1000 OR p_stake % 100 <> 0) THEN
    RAISE EXCEPTION 'Stake must be 0 or 200 to 1000 RPS Chips in 100-chip increments'
      USING ERRCODE='22023';
  END IF;

  SELECT * INTO v_player
  FROM public.rps_players
  WHERE auth_user_id = v_uid
  FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Create/load a free-play profile first' USING ERRCODE='P0002';
  END IF;

  -- This existing RPC enforces the current profile/balance locks and format rules.
  -- Its generated code remains inside this function and is deliberately discarded.
  v_created := public.rps_v2_create_room(p_max_players, p_mode, p_stake);
  v_room_id := NULLIF(v_created->>'room_id', '')::uuid;
  IF v_room_id IS NULL THEN
    RAISE EXCEPTION 'Could not create open table' USING ERRCODE='P0001';
  END IF;

  UPDATE public.rps_rooms
  SET visibility = 'open'
  WHERE id = v_room_id
    AND p1_player_id = v_player.id
    AND status = 'waiting'
    AND visibility = 'private';
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Could not publish open table' USING ERRCODE='P0001';
  END IF;

  SELECT * INTO v_room FROM public.rps_rooms WHERE id = v_room_id;
  RETURN jsonb_build_object(
    'room_id', v_room.id,
    'visibility', 'open',
    'status', v_room.status,
    'mode', v_room.mode,
    'max_rounds', v_room.max_rounds,
    'max_players', v_room.max_players,
    'players_joined', 1,
    'stake', COALESCE(v_room.stake, 0),
    'pot', COALESCE(v_room.stake, 0) * v_room.max_players
  );
END;
$function$;

-- Return only minimal card fields. In particular this projection contains no room code,
-- player IDs, names, or other room data. A room UUID is only usable with the guarded join RPC.
CREATE OR REPLACE FUNCTION public.rps_v2_list_open_rooms(p_limit integer DEFAULT 50)
RETURNS TABLE (
  room_id uuid,
  stake integer,
  mode text,
  max_rounds integer,
  max_players smallint,
  players_joined integer
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'pg_catalog', 'public'
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_player_id uuid;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'Authentication required' USING ERRCODE='28000';
  END IF;

  SELECT p.id INTO v_player_id
  FROM public.rps_players p
  WHERE p.auth_user_id = v_uid;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Create/load a free-play profile first' USING ERRCODE='P0002';
  END IF;

  RETURN QUERY
  SELECT r.id,
         COALESCE(r.stake, 0)::integer,
         r.mode,
         COALESCE(r.max_rounds, CASE r.mode WHEN 'best3' THEN 3 ELSE 5 END)::integer,
         r.max_players,
         ((r.p1_player_id IS NOT NULL)::integer
          + (r.p2_player_id IS NOT NULL)::integer
          + (r.p3_player_id IS NOT NULL)::integer)::integer
  FROM public.rps_rooms r
  WHERE r.visibility = 'open'
    AND r.status = 'waiting'
    AND r.match_finished_at IS NULL
    AND r.p1_player_id IS NOT NULL
    AND NOT (v_player_id = ANY(array_remove(
      ARRAY[r.p1_player_id,r.p2_player_id,r.p3_player_id]::uuid[], NULL)))
    AND (r.p2_player_id IS NULL OR (r.max_players = 3 AND r.p3_player_id IS NULL))
    AND r.mode IN ('best3', 'best5')
    AND COALESCE(r.max_rounds, 0) IN (3, 5)
    AND (COALESCE(r.stake, 0) = 0 OR
         (r.stake BETWEEN 200 AND 1000 AND r.stake % 100 = 0))
  ORDER BY COALESCE(r.stake, 0), r.mode, r.max_players, r.id
  LIMIT LEAST(100, GREATEST(COALESCE(p_limit, 50), 1));
END;
$function$;

-- Lock in the same profile-then-room order as the existing join RPC. Recheck visibility,
-- waiting state, and capacity while locked, then delegate the seat/balance/stake safeguards.
CREATE OR REPLACE FUNCTION public.rps_v2_join_open_room(
  p_room_id uuid,
  p_accept_stake boolean DEFAULT false
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog', 'public'
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_player public.rps_players%ROWTYPE;
  v_room public.rps_rooms%ROWTYPE;
  v_joined jsonb;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'Authentication required' USING ERRCODE='28000';
  END IF;
  IF p_room_id IS NULL THEN
    RAISE EXCEPTION 'Open table is no longer available' USING ERRCODE='P0002';
  END IF;

  SELECT * INTO v_player
  FROM public.rps_players
  WHERE auth_user_id = v_uid
  FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Create/load a free-play profile first' USING ERRCODE='P0002';
  END IF;

  SELECT * INTO v_room
  FROM public.rps_rooms
  WHERE id = p_room_id
  FOR UPDATE;
  IF NOT FOUND OR v_room.visibility <> 'open' OR v_room.status <> 'waiting'
     OR v_room.match_finished_at IS NOT NULL
     OR v_player.id = ANY(array_remove(
          ARRAY[v_room.p1_player_id,v_room.p2_player_id,v_room.p3_player_id]::uuid[], NULL))
     OR (v_room.p2_player_id IS NOT NULL
         AND (v_room.max_players <> 3 OR v_room.p3_player_id IS NOT NULL)) THEN
    RAISE EXCEPTION 'Open table is no longer available' USING ERRCODE='55000';
  END IF;

  -- Existing join RPC rechecks slot availability, row locks, account eligibility, balances,
  -- reserved active wagers, and explicit wager acceptance. Never return its room code here.
  v_joined := public.rps_v2_join_room(v_room.room_code, COALESCE(p_accept_stake, false));
  RETURN (v_joined - 'room_code') || jsonb_build_object(
    'room_id', v_room.id,
    'visibility', 'open'
  );
END;
$function$;

REVOKE ALL ON FUNCTION public.rps_v2_create_open_room(smallint, text, integer)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.rps_v2_create_open_room(smallint, text, integer)
  TO authenticated;
REVOKE ALL ON FUNCTION public.rps_v2_list_open_rooms(integer)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.rps_v2_list_open_rooms(integer)
  TO authenticated;
REVOKE ALL ON FUNCTION public.rps_v2_join_open_room(uuid, boolean)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.rps_v2_join_open_room(uuid, boolean)
  TO authenticated;

INSERT INTO supabase_migrations.schema_migrations (version, name, created_by)
VALUES ('20261001103000', 'rps_open_tables_20261001', 'zapia')
ON CONFLICT DO NOTHING;

NOTIFY pgrst, 'reload schema';
COMMIT;
