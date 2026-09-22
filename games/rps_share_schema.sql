create table if not exists public.rps_share_rewards (
  id uuid primary key default gen_random_uuid(),
  player_id uuid not null references public.rps_players(id) on delete cascade,
  reward_date date not null default current_date,
  reward integer not null default 100 check (reward > 0),
  created_at timestamptz not null default now(),
  unique(player_id, reward_date)
);
grant select, insert on public.rps_share_rewards to anon, authenticated;
