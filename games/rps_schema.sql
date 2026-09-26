create table if not exists public.rps_rooms (
  id uuid primary key default gen_random_uuid(),
  room_code text not null unique,
  max_players smallint not null default 2 check (max_players in (2,3)),
  p1_id text not null,
  p1_name text not null,
  p2_id text,
  p2_name text,
  p3_id text,
  p3_name text,
  status text not null default 'waiting' check (status in ('waiting','playing','closed')),
  round_number integer not null default 1,
  p1_move text check (p1_move is null or p1_move in ('rock','paper','scissors')),
  p2_move text check (p2_move is null or p2_move in ('rock','paper','scissors')),
  p3_move text check (p3_move is null or p3_move in ('rock','paper','scissors')),
  result text check (result is null or result in ('p1','p2','p3','multi','draw')),
  winner_id text,
  winner_ids text[] not null default array[]::text[],
  match_finished_at timestamptz,
  match_winner_ids text[] not null default array[]::text[],
  p1_score integer not null default 0,
  p2_score integer not null default 0,
  p3_score integer not null default 0,
  created_at timestamptz not null default now()
);
grant select, insert, update on public.rps_rooms to anon, authenticated;
create index if not exists rps_rooms_code_status on public.rps_rooms(room_code,status);
