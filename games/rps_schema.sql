create table if not exists public.rps_rooms (
  id uuid primary key default gen_random_uuid(),
  room_code text not null unique,
  p1_id text not null,
  p1_name text not null,
  p2_id text,
  p2_name text,
  status text not null default 'waiting' check (status in ('waiting','playing','closed')),
  round_number integer not null default 1,
  p1_move text check (p1_move is null or p1_move in ('rock','paper','scissors')),
  p2_move text check (p2_move is null or p2_move in ('rock','paper','scissors')),
  result text check (result is null or result in ('p1','p2','draw')),
  winner_id text,
  p1_score integer not null default 0,
  p2_score integer not null default 0,
  created_at timestamptz not null default now()
);
grant select, insert, update on public.rps_rooms to anon, authenticated;
create index if not exists rps_rooms_code_status on public.rps_rooms(room_code,status);
