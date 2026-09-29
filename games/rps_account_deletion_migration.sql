-- Secure server-only cleanup for a player's own Orcinos RPS data.
-- Auth user deletion is performed afterward by the delete-rps-account Edge Function.
BEGIN;

CREATE OR REPLACE FUNCTION public.rps_v2_admin_delete_account_data(p_user_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $function$
DECLARE
  v_player_ids uuid[] := ARRAY[]::uuid[];
  v_usernames text[] := ARRAY[]::text[];
  v_players_deleted integer := 0;
BEGIN
  IF p_user_id IS NULL THEN
    RAISE EXCEPTION 'User ID is required' USING ERRCODE = '22023';
  END IF;

  SELECT coalesce(array_agg(id), ARRAY[]::uuid[]),
         coalesce(array_agg(username), ARRAY[]::text[])
    INTO v_player_ids, v_usernames
  FROM public.rps_players
  WHERE auth_user_id = p_user_id;

  -- Remove the player's private room messages.
  DELETE FROM public.rps_room_messages WHERE player_id = ANY(v_player_ids);
  DELETE FROM public.rps_messages WHERE player_id = ANY(v_player_ids);

  -- Remove the player's match history, and replace their name in opponents' history.
  UPDATE public.rps_match_history
     SET opponent_name = 'Deleted player'
   WHERE opponent_name = ANY(v_usernames);
  DELETE FROM public.rps_match_history WHERE player_id = ANY(v_player_ids);
  DELETE FROM public.rps_share_rewards WHERE player_id = ANY(v_player_ids);

  -- Retain anonymous opponent match rows while removing the deleted player's identity and moves.
  UPDATE public.rps_matches
     SET player_one_id = NULL, player_one_move = NULL
   WHERE player_one_id = ANY(v_player_ids);
  UPDATE public.rps_matches
     SET player_two_id = NULL, player_two_move = NULL
   WHERE player_two_id = ANY(v_player_ids);

  -- Preserve completed rooms for other players, but remove this player's identifying details.
  -- In-progress rooms are closed so no one is left in a stuck match.
  UPDATE public.rps_rooms
     SET p1_id = CASE WHEN p1_player_id = ANY(v_player_ids) THEN 'deleted' ELSE p1_id END,
         p1_name = CASE WHEN p1_player_id = ANY(v_player_ids) THEN 'Deleted player' ELSE p1_name END,
         p1_player_id = CASE WHEN p1_player_id = ANY(v_player_ids) THEN NULL ELSE p1_player_id END,
         p1_move = CASE WHEN p1_player_id = ANY(v_player_ids) THEN NULL ELSE p1_move END,
         p1_score = CASE WHEN p1_player_id = ANY(v_player_ids) THEN 0 ELSE p1_score END,
         p2_id = CASE WHEN p2_player_id = ANY(v_player_ids) THEN 'deleted' ELSE p2_id END,
         p2_name = CASE WHEN p2_player_id = ANY(v_player_ids) THEN 'Deleted player' ELSE p2_name END,
         p2_player_id = CASE WHEN p2_player_id = ANY(v_player_ids) THEN NULL ELSE p2_player_id END,
         p2_move = CASE WHEN p2_player_id = ANY(v_player_ids) THEN NULL ELSE p2_move END,
         p2_score = CASE WHEN p2_player_id = ANY(v_player_ids) THEN 0 ELSE p2_score END,
         p3_id = CASE WHEN p3_player_id = ANY(v_player_ids) THEN 'deleted' ELSE p3_id END,
         p3_name = CASE WHEN p3_player_id = ANY(v_player_ids) THEN 'Deleted player' ELSE p3_name END,
         p3_player_id = CASE WHEN p3_player_id = ANY(v_player_ids) THEN NULL ELSE p3_player_id END,
         p3_move = CASE WHEN p3_player_id = ANY(v_player_ids) THEN NULL ELSE p3_move END,
         p3_score = CASE WHEN p3_player_id = ANY(v_player_ids) THEN 0 ELSE p3_score END,
         status = CASE WHEN status IN ('waiting','playing') THEN 'closed' ELSE status END,
         match_finished_at = CASE WHEN status IN ('waiting','playing') THEN coalesce(match_finished_at, now()) ELSE match_finished_at END,
         result = NULL,
         winner_id = NULL,
         winner_ids = ARRAY[]::text[],
         match_winner_ids = ARRAY[]::text[],
         round_winner_player_ids = ARRAY[]::uuid[]
   WHERE p1_player_id = ANY(v_player_ids)
      OR p2_player_id = ANY(v_player_ids)
      OR p3_player_id = ANY(v_player_ids);

  -- Remove the player's legacy wager/chip account and rooms. Preserve opponents' ledger
  -- entries, but detach them from a room that is being removed.
  UPDATE public.rps_wager_ledger
     SET room_id = NULL
   WHERE room_id IN (
     SELECT id FROM public.rps_wager_rooms
      WHERE p1_user_id = p_user_id OR p2_user_id = p_user_id
   );
  DELETE FROM public.rps_wager_ledger WHERE user_id = p_user_id;
  DELETE FROM public.rps_wager_rounds
   WHERE room_id IN (
     SELECT id FROM public.rps_wager_rooms
      WHERE p1_user_id = p_user_id OR p2_user_id = p_user_id
   );
  DELETE FROM public.rps_wager_rooms
   WHERE p1_user_id = p_user_id OR p2_user_id = p_user_id;
  DELETE FROM public.rps_wager_accounts WHERE user_id = p_user_id;

  -- Remove account-scoped progression and relationships before deleting the profile.
  DELETE FROM public.rps_daily_goal_claims WHERE player_id = ANY(v_player_ids);
  DELETE FROM public.rps_achievements WHERE player_id = ANY(v_player_ids);
  DELETE FROM public.rps_friend_requests
   WHERE requester_player_id = ANY(v_player_ids) OR recipient_player_id = ANY(v_player_ids);
  DELETE FROM public.rps_friendships
   WHERE player_low_id = ANY(v_player_ids) OR player_high_id = ANY(v_player_ids);
  DELETE FROM public.rps_referral_codes WHERE player_id = ANY(v_player_ids);
  DELETE FROM public.rps_referral_rewards
   WHERE referred_auth_user_id = p_user_id
      OR inviter_player_id = ANY(v_player_ids)
      OR referred_player_id = ANY(v_player_ids);

  DELETE FROM public.rps_players WHERE auth_user_id = p_user_id;
  GET DIAGNOSTICS v_players_deleted = ROW_COUNT;

  RETURN jsonb_build_object('players_deleted', v_players_deleted);
END;
$function$;

REVOKE ALL ON FUNCTION public.rps_v2_admin_delete_account_data(uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.rps_v2_admin_delete_account_data(uuid) TO service_role;

COMMIT;
