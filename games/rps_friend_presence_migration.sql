-- RPS friend presence is private to accepted friends and expires after a short heartbeat window.
-- Only one mutable state row is stored per authenticated player; no room ID or game details are exposed.

CREATE TABLE IF NOT EXISTS public.rps_player_presence (
  auth_user_id uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  activity text NOT NULL DEFAULT 'online' CHECK (activity IN ('online', 'playing')),
  last_seen_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.rps_player_presence ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.rps_player_presence FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.rps_presence_heartbeat(p_activity text DEFAULT 'online')
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog', 'public'
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_player_id uuid;
  v_activity text := coalesce(p_activity, 'online');
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'Authentication required' USING ERRCODE = '28000';
  END IF;

  IF EXISTS (
    SELECT 1 FROM auth.users u
    WHERE u.id = v_uid AND coalesce(u.is_anonymous, false)
  ) THEN
    RETURN jsonb_build_object('tracked', false, 'reason', 'registered_account_required');
  END IF;

  IF v_activity NOT IN ('online', 'playing') THEN
    RAISE EXCEPTION 'Invalid presence activity' USING ERRCODE = '22023';
  END IF;

  SELECT p.id INTO v_player_id
  FROM public.rps_players p
  WHERE p.auth_user_id = v_uid;

  IF v_player_id IS NULL THEN
    RETURN jsonb_build_object('tracked', false, 'reason', 'profile_required');
  END IF;

  INSERT INTO public.rps_player_presence (auth_user_id, activity, last_seen_at)
  VALUES (v_uid, v_activity, clock_timestamp())
  ON CONFLICT (auth_user_id) DO UPDATE
    SET activity = EXCLUDED.activity,
        last_seen_at = EXCLUDED.last_seen_at;

  RETURN jsonb_build_object('tracked', true, 'activity', v_activity);
END;
$function$;

CREATE OR REPLACE FUNCTION public.rps_presence_offline()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog', 'public'
AS $function$
DECLARE
  v_uid uuid := auth.uid();
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'Authentication required' USING ERRCODE = '28000';
  END IF;

  DELETE FROM public.rps_player_presence
  WHERE auth_user_id = v_uid;

  RETURN jsonb_build_object('offline', true);
END;
$function$;

CREATE OR REPLACE FUNCTION public.rps_friends_presence()
RETURNS TABLE(username text, avatar text, presence text)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'pg_catalog', 'public'
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_me_id uuid;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'Authentication required' USING ERRCODE = '28000';
  END IF;

  IF EXISTS (
    SELECT 1 FROM auth.users u
    WHERE u.id = v_uid AND coalesce(u.is_anonymous, false)
  ) THEN
    RAISE EXCEPTION 'A registered account is required for friends' USING ERRCODE = '28000';
  END IF;

  SELECT p.id INTO v_me_id
  FROM public.rps_players p
  WHERE p.auth_user_id = v_uid;

  IF v_me_id IS NULL THEN
    RAISE EXCEPTION 'Authenticated player profile required' USING ERRCODE = 'P0002';
  END IF;

  RETURN QUERY
  SELECT
    friend.username,
    coalesce(friend.avatar, '🦊')::text,
    CASE
      WHEN presence.last_seen_at >= now() - interval '90 seconds'
        THEN CASE WHEN presence.activity = 'playing' THEN 'playing' ELSE 'online' END
      ELSE 'offline'
    END::text AS presence
  FROM public.rps_friendships f
  JOIN public.rps_players friend
    ON friend.id = CASE
      WHEN f.player_low_id = v_me_id THEN f.player_high_id
      ELSE f.player_low_id
    END
  LEFT JOIN public.rps_player_presence presence
    ON presence.auth_user_id = friend.auth_user_id
  WHERE v_me_id IN (f.player_low_id, f.player_high_id)
    AND friend.auth_user_id IS NOT NULL
    AND EXISTS (
      SELECT 1 FROM auth.users u
      WHERE u.id = friend.auth_user_id
        AND NOT coalesce(u.is_anonymous, false)
    )
  ORDER BY friend.username;
END;
$function$;

REVOKE ALL ON FUNCTION public.rps_presence_heartbeat(text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.rps_presence_offline() FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.rps_friends_presence() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.rps_presence_heartbeat(text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.rps_presence_offline() TO authenticated;
GRANT EXECUTE ON FUNCTION public.rps_friends_presence() TO authenticated;
