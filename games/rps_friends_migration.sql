-- Additive Rock/Paper/Scissors friend system.
-- Additive RPS friend and request schema with authenticated RPC access only.
-- Prerequisite: the existing public.rps_players table has id (uuid), auth_user_id
-- (uuid), username (text), and avatar_key (text); the existing authenticated profile
-- system must keep usernames unique after case/whitespace normalization. The unique
-- index below deliberately fails closed if legacy duplicate usernames need cleanup.

BEGIN;

DO $preflight$
DECLARE v_missing text;
BEGIN
  SELECT string_agg(x.column_name, ', ' ORDER BY x.column_name) INTO v_missing
  FROM (VALUES ('id'),('auth_user_id'),('username'),('avatar')) AS x(column_name)
  LEFT JOIN information_schema.columns c ON c.table_schema='public'
    AND c.table_name='rps_players' AND c.column_name=x.column_name
  WHERE c.column_name IS NULL;
  IF v_missing IS NOT NULL THEN
    RAISE EXCEPTION 'Friend migration needs public.rps_players columns: %', v_missing;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='auth' AND table_name='users' AND column_name='is_anonymous') THEN
    RAISE EXCEPTION 'Friend migration requires auth.users.is_anonymous to distinguish guest accounts';
  END IF;
  IF EXISTS (SELECT 1 FROM public.rps_players WHERE auth_user_id IS NOT NULL
    GROUP BY lower(btrim(username)) HAVING count(*) > 1) THEN
    RAISE EXCEPTION 'Duplicate authenticated usernames exist; resolve them before applying friend migration';
  END IF;
END;
$preflight$;

-- Username is the public handle used by the UI and server-side resolver.
CREATE UNIQUE INDEX IF NOT EXISTS rps_players_auth_username_norm_uidx
  ON public.rps_players (lower(btrim(username))) WHERE auth_user_id IS NOT NULL;

CREATE TABLE IF NOT EXISTS public.rps_friend_requests (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  requester_player_id uuid NOT NULL REFERENCES public.rps_players(id) ON DELETE CASCADE,
  recipient_player_id uuid NOT NULL REFERENCES public.rps_players(id) ON DELETE CASCADE,
  status text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending','accepted','declined')),
  created_at timestamptz NOT NULL DEFAULT now(),
  responded_at timestamptz,
  CONSTRAINT rps_friend_requests_not_self CHECK (requester_player_id <> recipient_player_id)
);
CREATE UNIQUE INDEX IF NOT EXISTS rps_friend_requests_pending_pair_uidx
  ON public.rps_friend_requests(requester_player_id,recipient_player_id) WHERE status='pending';
CREATE INDEX IF NOT EXISTS rps_friend_requests_recipient_idx
  ON public.rps_friend_requests(recipient_player_id,status,created_at DESC);
CREATE INDEX IF NOT EXISTS rps_friend_requests_requester_idx
  ON public.rps_friend_requests(requester_player_id,status,created_at DESC);

CREATE TABLE IF NOT EXISTS public.rps_friendships (
  player_low_id uuid NOT NULL REFERENCES public.rps_players(id) ON DELETE CASCADE,
  player_high_id uuid NOT NULL REFERENCES public.rps_players(id) ON DELETE CASCADE,
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (player_low_id,player_high_id),
  CONSTRAINT rps_friendships_ordered CHECK (player_low_id < player_high_id)
);
CREATE INDEX IF NOT EXISTS rps_friendships_high_idx ON public.rps_friendships(player_high_id);

ALTER TABLE public.rps_friend_requests ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.rps_friendships ENABLE ROW LEVEL SECURITY;
-- No direct client access or policies: all operations go through the authenticated RPCs.
REVOKE ALL ON TABLE public.rps_friend_requests, public.rps_friendships FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.rps_friends_search(p_query text)
RETURNS TABLE(username text, avatar text)
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path = pg_catalog, public
AS $function$
DECLARE v_uid uuid := auth.uid(); v_query text := btrim(coalesce(p_query,''));
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Authentication required' USING ERRCODE='28000'; END IF;
  IF EXISTS (SELECT 1 FROM auth.users u WHERE u.id=v_uid AND coalesce(u.is_anonymous,false)) THEN RAISE EXCEPTION 'A registered account is required for friends' USING ERRCODE='28000'; END IF;
  IF char_length(v_query) NOT BETWEEN 2 AND 24 OR v_query ~ '[[:cntrl:]]' THEN
    RAISE EXCEPTION 'Enter 2 to 24 characters to search' USING ERRCODE='22023';
  END IF;
  RETURN QUERY
    SELECT p.username,p.avatar FROM public.rps_players p
    WHERE p.auth_user_id IS NOT NULL
      AND lower(p.username) LIKE '%' || lower(v_query) || '%'
      AND p.auth_user_id <> v_uid
      AND EXISTS (SELECT 1 FROM auth.users u WHERE u.id=p.auth_user_id AND NOT coalesce(u.is_anonymous,false))
    ORDER BY p.username LIMIT 10;
END;
$function$;

CREATE OR REPLACE FUNCTION public.rps_friends_send_request(p_username text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, public
AS $function$
DECLARE v_uid uuid := auth.uid(); v_sender public.rps_players%ROWTYPE;
  v_target public.rps_players%ROWTYPE; v_count integer; v_low uuid; v_high uuid;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Authentication required' USING ERRCODE='28000'; END IF;
  IF EXISTS (SELECT 1 FROM auth.users u WHERE u.id=v_uid AND coalesce(u.is_anonymous,false)) THEN RAISE EXCEPTION 'A registered account is required for friends' USING ERRCODE='28000'; END IF;
  IF p_username IS NULL OR char_length(btrim(p_username)) NOT BETWEEN 1 AND 24 THEN
    RAISE EXCEPTION 'Invalid username' USING ERRCODE='22023';
  END IF;
  SELECT * INTO v_sender FROM public.rps_players WHERE auth_user_id=v_uid FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Authenticated player profile required' USING ERRCODE='P0002'; END IF;
  SELECT * INTO v_target FROM public.rps_players p
    WHERE p.auth_user_id IS NOT NULL AND lower(btrim(p.username))=lower(btrim(p_username))
      AND EXISTS (SELECT 1 FROM auth.users u WHERE u.id=p.auth_user_id AND NOT coalesce(u.is_anonymous,false));
  IF NOT FOUND THEN RAISE EXCEPTION 'Username not found' USING ERRCODE='P0002'; END IF;
  IF v_target.id=v_sender.id THEN RAISE EXCEPTION 'You cannot friend yourself' USING ERRCODE='22023'; END IF;
  v_low:=least(v_sender.id,v_target.id); v_high:=greatest(v_sender.id,v_target.id);
  PERFORM pg_advisory_xact_lock(hashtextextended(v_low::text || ':' || v_high::text,0));
  IF EXISTS (SELECT 1 FROM public.rps_friendships f WHERE f.player_low_id=v_low AND f.player_high_id=v_high) THEN
    RAISE EXCEPTION 'Already friends' USING ERRCODE='23505';
  END IF;
  IF EXISTS (SELECT 1 FROM public.rps_friend_requests r WHERE r.status='pending'
      AND ((r.requester_player_id=v_sender.id AND r.recipient_player_id=v_target.id)
        OR (r.requester_player_id=v_target.id AND r.recipient_player_id=v_sender.id))) THEN
    RAISE EXCEPTION 'A pending request already exists between these players' USING ERRCODE='23505';
  END IF;
  -- Serialize sends for this account before checking the daily cap.
  SELECT count(*) INTO v_count FROM public.rps_friend_requests r
    WHERE r.requester_player_id=v_sender.id AND r.created_at >= date_trunc('day',now());
  IF v_count >= 20 THEN RAISE EXCEPTION 'Daily friend request limit reached' USING ERRCODE='54000'; END IF;
  INSERT INTO public.rps_friend_requests(requester_player_id,recipient_player_id)
    VALUES(v_sender.id,v_target.id);
  RETURN jsonb_build_object('sent',true,'username',v_target.username);
END;
$function$;

CREATE OR REPLACE FUNCTION public.rps_friends_list()
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path = pg_catalog, public
AS $function$
DECLARE v_uid uuid := auth.uid(); v_me public.rps_players%ROWTYPE;
  v_friends jsonb; v_incoming jsonb; v_outgoing jsonb;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Authentication required' USING ERRCODE='28000'; END IF;
  IF EXISTS (SELECT 1 FROM auth.users u WHERE u.id=v_uid AND coalesce(u.is_anonymous,false)) THEN RAISE EXCEPTION 'A registered account is required for friends' USING ERRCODE='28000'; END IF;
  SELECT * INTO v_me FROM public.rps_players WHERE auth_user_id=v_uid;
  IF NOT FOUND THEN RAISE EXCEPTION 'Authenticated player profile required' USING ERRCODE='P0002'; END IF;
  SELECT coalesce(jsonb_agg(jsonb_build_object('username',p.username,'avatar',p.avatar)
    ORDER BY p.username),'[]'::jsonb) INTO v_friends
  FROM public.rps_friendships f JOIN public.rps_players p
    ON p.id=CASE WHEN f.player_low_id=v_me.id THEN f.player_high_id ELSE f.player_low_id END
  WHERE v_me.id IN (f.player_low_id,f.player_high_id) AND p.auth_user_id IS NOT NULL
    AND EXISTS (SELECT 1 FROM auth.users u WHERE u.id=p.auth_user_id AND NOT coalesce(u.is_anonymous,false));
  SELECT coalesce(jsonb_agg(jsonb_build_object('username',p.username,'avatar',p.avatar)
    ORDER BY r.created_at),'[]'::jsonb) INTO v_incoming
  FROM public.rps_friend_requests r JOIN public.rps_players p ON p.id=r.requester_player_id
  WHERE r.recipient_player_id=v_me.id AND r.status='pending' AND p.auth_user_id IS NOT NULL
    AND EXISTS (SELECT 1 FROM auth.users u WHERE u.id=p.auth_user_id AND NOT coalesce(u.is_anonymous,false));
  SELECT coalesce(jsonb_agg(jsonb_build_object('username',p.username,'avatar',p.avatar)
    ORDER BY r.created_at),'[]'::jsonb) INTO v_outgoing
  FROM public.rps_friend_requests r JOIN public.rps_players p ON p.id=r.recipient_player_id
  WHERE r.requester_player_id=v_me.id AND r.status='pending' AND p.auth_user_id IS NOT NULL
    AND EXISTS (SELECT 1 FROM auth.users u WHERE u.id=p.auth_user_id AND NOT coalesce(u.is_anonymous,false));
  RETURN jsonb_build_object('friends',v_friends,'incoming',v_incoming,'outgoing',v_outgoing);
END;
$function$;

CREATE OR REPLACE FUNCTION public.rps_friends_accept(p_username text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, public
AS $function$
DECLARE v_uid uuid := auth.uid(); v_me public.rps_players%ROWTYPE;
  v_other public.rps_players%ROWTYPE; v_low uuid; v_high uuid; v_rows integer;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Authentication required' USING ERRCODE='28000'; END IF;
  IF EXISTS (SELECT 1 FROM auth.users u WHERE u.id=v_uid AND coalesce(u.is_anonymous,false)) THEN RAISE EXCEPTION 'A registered account is required for friends' USING ERRCODE='28000'; END IF;
  SELECT * INTO v_me FROM public.rps_players WHERE auth_user_id=v_uid;
  IF NOT FOUND THEN RAISE EXCEPTION 'Authenticated player profile required' USING ERRCODE='P0002'; END IF;
  SELECT * INTO v_other FROM public.rps_players p WHERE p.auth_user_id IS NOT NULL
    AND EXISTS (SELECT 1 FROM auth.users u WHERE u.id=p.auth_user_id AND NOT coalesce(u.is_anonymous,false))
    AND lower(btrim(p.username))=lower(btrim(coalesce(p_username,'')));
  IF NOT FOUND OR v_other.id=v_me.id THEN RAISE EXCEPTION 'Incoming request not found' USING ERRCODE='P0002'; END IF;
  UPDATE public.rps_friend_requests SET status='accepted',responded_at=now()
    WHERE requester_player_id=v_other.id AND recipient_player_id=v_me.id AND status='pending';
  GET DIAGNOSTICS v_rows=ROW_COUNT;
  IF v_rows=0 THEN RAISE EXCEPTION 'Incoming request not found or no longer pending' USING ERRCODE='P0002'; END IF;
  v_low:=least(v_me.id,v_other.id); v_high:=greatest(v_me.id,v_other.id);
  INSERT INTO public.rps_friendships(player_low_id,player_high_id) VALUES(v_low,v_high)
    ON CONFLICT DO NOTHING;
  RETURN jsonb_build_object('accepted',true,'username',v_other.username);
END;
$function$;

CREATE OR REPLACE FUNCTION public.rps_friends_decline(p_username text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, public
AS $function$
DECLARE v_uid uuid := auth.uid(); v_me public.rps_players%ROWTYPE;
  v_other public.rps_players%ROWTYPE; v_rows integer;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Authentication required' USING ERRCODE='28000'; END IF;
  IF EXISTS (SELECT 1 FROM auth.users u WHERE u.id=v_uid AND coalesce(u.is_anonymous,false)) THEN RAISE EXCEPTION 'A registered account is required for friends' USING ERRCODE='28000'; END IF;
  SELECT * INTO v_me FROM public.rps_players WHERE auth_user_id=v_uid;
  IF NOT FOUND THEN RAISE EXCEPTION 'Authenticated player profile required' USING ERRCODE='P0002'; END IF;
  SELECT * INTO v_other FROM public.rps_players p WHERE p.auth_user_id IS NOT NULL
    AND EXISTS (SELECT 1 FROM auth.users u WHERE u.id=p.auth_user_id AND NOT coalesce(u.is_anonymous,false))
    AND lower(btrim(p.username))=lower(btrim(coalesce(p_username,'')));
  IF NOT FOUND OR v_other.id=v_me.id THEN RAISE EXCEPTION 'Incoming request not found' USING ERRCODE='P0002'; END IF;
  UPDATE public.rps_friend_requests SET status='declined',responded_at=now()
    WHERE requester_player_id=v_other.id AND recipient_player_id=v_me.id AND status='pending';
  GET DIAGNOSTICS v_rows=ROW_COUNT;
  IF v_rows=0 THEN RAISE EXCEPTION 'Incoming request not found or no longer pending' USING ERRCODE='P0002'; END IF;
  RETURN jsonb_build_object('declined',true);
END;
$function$;

CREATE OR REPLACE FUNCTION public.rps_friends_remove(p_username text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, public
AS $function$
DECLARE v_uid uuid := auth.uid(); v_me public.rps_players%ROWTYPE;
  v_other public.rps_players%ROWTYPE; v_low uuid; v_high uuid; v_rows integer;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Authentication required' USING ERRCODE='28000'; END IF;
  IF EXISTS (SELECT 1 FROM auth.users u WHERE u.id=v_uid AND coalesce(u.is_anonymous,false)) THEN RAISE EXCEPTION 'A registered account is required for friends' USING ERRCODE='28000'; END IF;
  SELECT * INTO v_me FROM public.rps_players WHERE auth_user_id=v_uid;
  IF NOT FOUND THEN RAISE EXCEPTION 'Authenticated player profile required' USING ERRCODE='P0002'; END IF;
  SELECT * INTO v_other FROM public.rps_players p WHERE p.auth_user_id IS NOT NULL
    AND EXISTS (SELECT 1 FROM auth.users u WHERE u.id=p.auth_user_id AND NOT coalesce(u.is_anonymous,false))
    AND lower(btrim(p.username))=lower(btrim(coalesce(p_username,'')));
  IF NOT FOUND OR v_other.id=v_me.id THEN RAISE EXCEPTION 'Friend not found' USING ERRCODE='P0002'; END IF;
  v_low:=least(v_me.id,v_other.id); v_high:=greatest(v_me.id,v_other.id);
  DELETE FROM public.rps_friendships WHERE player_low_id=v_low AND player_high_id=v_high;
  GET DIAGNOSTICS v_rows=ROW_COUNT;
  IF v_rows=0 THEN RAISE EXCEPTION 'Friendship not found' USING ERRCODE='P0002'; END IF;
  RETURN jsonb_build_object('removed',true);
END;
$function$;

REVOKE ALL ON FUNCTION public.rps_friends_search(text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.rps_friends_send_request(text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.rps_friends_list() FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.rps_friends_accept(text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.rps_friends_decline(text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.rps_friends_remove(text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.rps_friends_search(text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.rps_friends_send_request(text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.rps_friends_list() TO authenticated;
GRANT EXECUTE ON FUNCTION public.rps_friends_accept(text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.rps_friends_decline(text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.rps_friends_remove(text) TO authenticated;

NOTIFY pgrst, 'reload schema';
COMMIT;
