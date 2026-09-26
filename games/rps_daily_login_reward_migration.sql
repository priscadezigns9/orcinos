-- Award each saved guest profile a single 100 virtual-coin login bonus per day.
-- The profile's guest token identifies the saved profile; this is not an ADA payout.

CREATE OR REPLACE FUNCTION public.rps_claim_daily_login_reward(p_guest_token text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_player public.rps_players%ROWTYPE;
  v_rows integer;
  v_today date := current_date;
BEGIN
  IF p_guest_token IS NULL OR length(p_guest_token) < 8 THEN
    RETURN jsonb_build_object('claimed', false, 'reason', 'invalid_profile');
  END IF;

  SELECT * INTO v_player
  FROM public.rps_players
  WHERE guest_token = p_guest_token
  FOR UPDATE;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('claimed', false, 'reason', 'profile_not_found');
  END IF;

  INSERT INTO public.rps_share_rewards(player_id, reward_date, reward)
  VALUES (v_player.id, v_today, 100)
  ON CONFLICT (player_id, reward_date) DO NOTHING;

  GET DIAGNOSTICS v_rows = ROW_COUNT;
  IF v_rows = 0 THEN
    RETURN jsonb_build_object(
      'claimed', false,
      'already_claimed', true,
      'coins', v_player.coins,
      'reward_date', v_today
    );
  END IF;

  UPDATE public.rps_players
  SET coins = coins + 100,
      updated_at = now()
  WHERE id = v_player.id
  RETURNING * INTO v_player;

  RETURN jsonb_build_object(
    'claimed', true,
    'already_claimed', false,
    'reward', 100,
    'coins', v_player.coins,
    'reward_date', v_today
  );
END;
$$;

REVOKE ALL ON FUNCTION public.rps_claim_daily_login_reward(text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.rps_claim_daily_login_reward(text) TO anon, authenticated;
DROP FUNCTION IF EXISTS public.rps_claim_daily_share_reward(text);
NOTIFY pgrst, 'reload schema';
