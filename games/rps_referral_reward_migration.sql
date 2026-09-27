-- One-time 100-coin inviter reward after a brand-new authenticated RPS profile is created via an invite code.
-- Referral tables are private; all access is mediated by the authenticated SECURITY DEFINER RPCs below.

CREATE TABLE IF NOT EXISTS public.rps_referral_codes (
  player_id uuid PRIMARY KEY REFERENCES public.rps_players(id) ON DELETE CASCADE,
  code text NOT NULL UNIQUE CHECK (code ~ '^[A-F0-9]{16}$'),
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.rps_referral_rewards (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  inviter_player_id uuid NOT NULL REFERENCES public.rps_players(id) ON DELETE CASCADE,
  referred_player_id uuid NOT NULL UNIQUE REFERENCES public.rps_players(id) ON DELETE CASCADE,
  referred_auth_user_id uuid NOT NULL UNIQUE REFERENCES auth.users(id) ON DELETE CASCADE,
  referral_code text NOT NULL,
  reward_coins integer NOT NULL DEFAULT 100 CHECK (reward_coins = 100),
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT rps_referral_rewards_not_self CHECK (inviter_player_id <> referred_player_id)
);

CREATE INDEX IF NOT EXISTS rps_referral_rewards_inviter_idx
  ON public.rps_referral_rewards (inviter_player_id, created_at DESC);

ALTER TABLE public.rps_referral_codes ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.rps_referral_rewards ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.rps_referral_codes, public.rps_referral_rewards FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.rps_v2_get_my_referral_code()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog', 'public'
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_player_id uuid;
  v_code text;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'Authentication required' USING ERRCODE='28000';
  END IF;

  SELECT id INTO v_player_id
  FROM public.rps_players
  WHERE auth_user_id = v_uid;

  IF v_player_id IS NULL THEN
    RAISE EXCEPTION 'Create an RPS profile first' USING ERRCODE='P0001';
  END IF;

  INSERT INTO public.rps_referral_codes (player_id, code)
  VALUES (v_player_id, upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 16)))
  ON CONFLICT (player_id) DO NOTHING;

  SELECT code INTO v_code
  FROM public.rps_referral_codes
  WHERE player_id = v_player_id;

  RETURN jsonb_build_object('code', v_code);
END;
$function$;

CREATE OR REPLACE FUNCTION public.rps_v2_get_or_create_profile_with_referral(
  p_username text,
  p_avatar_key text DEFAULT 'starter'::text,
  p_referral_code text DEFAULT NULL::text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog', 'public'
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_had_profile boolean := false;
  v_profile jsonb;
  v_referred_player_id uuid;
  v_inviter_player_id uuid;
  v_referral_code text := upper(btrim(coalesce(p_referral_code, '')));
  v_inserted integer := 0;
  v_updated integer := 0;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'Authentication required' USING ERRCODE='28000';
  END IF;

  SELECT EXISTS (
    SELECT 1 FROM public.rps_players WHERE auth_user_id = v_uid
  ) INTO v_had_profile;

  v_profile := public.rps_v2_get_or_create_profile(p_username, p_avatar_key);

  SELECT id INTO v_referred_player_id
  FROM public.rps_players
  WHERE auth_user_id = v_uid;

  IF NOT v_had_profile AND v_referral_code ~ '^[A-F0-9]{16}$' THEN
    SELECT player_id INTO v_inviter_player_id
    FROM public.rps_referral_codes
    WHERE code = v_referral_code;

    IF v_inviter_player_id IS NOT NULL AND v_inviter_player_id <> v_referred_player_id THEN
      INSERT INTO public.rps_referral_rewards (
        inviter_player_id, referred_player_id, referred_auth_user_id, referral_code, reward_coins
      ) VALUES (
        v_inviter_player_id, v_referred_player_id, v_uid, v_referral_code, 100
      )
      ON CONFLICT DO NOTHING;

      GET DIAGNOSTICS v_inserted = ROW_COUNT;

      IF v_inserted = 1 THEN
        UPDATE public.rps_players
        SET coins = coins + 100, updated_at = now()
        WHERE id = v_inviter_player_id;

        GET DIAGNOSTICS v_updated = ROW_COUNT;
        IF v_updated <> 1 THEN
          RAISE EXCEPTION 'Referrer profile could not be updated' USING ERRCODE='P0001';
        END IF;

        v_profile := v_profile || jsonb_build_object('inviter_reward_coins_awarded', 100);
      END IF;
    END IF;
  END IF;

  RETURN v_profile;
END;
$function$;

REVOKE ALL ON FUNCTION public.rps_v2_get_my_referral_code() FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.rps_v2_get_or_create_profile_with_referral(text, text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.rps_v2_get_my_referral_code() TO authenticated;
GRANT EXECUTE ON FUNCTION public.rps_v2_get_or_create_profile_with_referral(text, text, text) TO authenticated;

INSERT INTO supabase_migrations.schema_migrations (version, name, created_by)
VALUES ('20260927230500', 'rps_referral_reward_20260927', 'zapia')
ON CONFLICT DO NOTHING;
