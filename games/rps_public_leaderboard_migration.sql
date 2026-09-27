-- Read-only public ranking endpoint for the RPS hub.
-- Exposes only intended display/ranking fields; it never returns guest tokens,
-- authentication IDs, room IDs, or per-match history.
BEGIN;

CREATE OR REPLACE FUNCTION public.rps_v2_get_leaderboard(p_limit integer DEFAULT 10)
RETURNS TABLE (
  username text,
  avatar_key text,
  wins integer,
  losses integer,
  draws integer,
  level integer,
  xp integer
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $function$
  SELECT p.username, p.avatar_key, p.wins, p.losses, p.draws, p.level, p.xp
  FROM public.rps_players AS p
  ORDER BY p.wins DESC, p.xp DESC, p.created_at ASC, p.username ASC
  LIMIT LEAST(GREATEST(COALESCE(p_limit, 10), 1), 50);
$function$;

REVOKE ALL ON FUNCTION public.rps_v2_get_leaderboard(integer) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.rps_v2_get_leaderboard(integer) TO anon, authenticated;

NOTIFY pgrst, 'reload schema';
COMMIT;
