-- RPS game progression: virtual coins only, never real-money betting.
create table if not exists public.rps_players (
  id uuid primary key default gen_random_uuid(),
  guest_token text unique not null,
  username text not null,
  avatar_key text not null default 'starter',
  coins integer not null default 1000 check (coins >= 0),
  xp integer not null default 0 check (xp >= 0),
  level integer not null default 1 check (level >= 1),
  wins integer not null default 0,
  losses integer not null default 0,
  draws integer not null default 0,
  current_streak integer not null default 0,
  best_streak integer not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create table if not exists public.rps_matches (
  id uuid primary key default gen_random_uuid(),
  room_id uuid references public.rps_rooms(id) on delete set null,
  player_one_id uuid references public.rps_players(id) on delete set null,
  player_two_id uuid references public.rps_players(id) on delete set null,
  player_one_move text,
  player_two_move text,
  outcome text check (outcome is null or outcome in ('player_one','player_two','draw')),
  stake integer not null default 0 check (stake >= 0),
  created_at timestamptz not null default now()
);
create table if not exists public.rps_achievements (
  id uuid primary key default gen_random_uuid(),
  player_id uuid not null references public.rps_players(id) on delete cascade,
  achievement_key text not null,
  unlocked_at timestamptz not null default now(),
  unique(player_id, achievement_key)
);
alter table public.rps_rooms add column if not exists p1_player_id uuid references public.rps_players(id) on delete set null;
alter table public.rps_rooms add column if not exists p2_player_id uuid references public.rps_players(id) on delete set null;
alter table public.rps_rooms add column if not exists stake integer not null default 0;
grant select, insert, update on public.rps_players to anon, authenticated;
grant select, insert, update on public.rps_matches to anon, authenticated;
grant select, insert on public.rps_achievements to anon, authenticated;
create index if not exists rps_players_leaderboard on public.rps_players(wins desc, xp desc);
create or replace function public.rps_set_updated_at() returns trigger language plpgsql as $$ begin new.updated_at=now(); return new; end; $$;
drop trigger if exists rps_players_updated_at on public.rps_players;
create trigger rps_players_updated_at before update on public.rps_players for each row execute function public.rps_set_updated_at();
