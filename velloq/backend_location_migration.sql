-- [Zapia] Velloq privacy-first location backend migration — 2026-07-30
-- Designed for the Orcinos Supabase project. Uses public schema because the
-- former orcinos schema is not exposed through the current API surface.

create extension if not exists pgcrypto;

create table if not exists v_tenants (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  created_at timestamptz not null default now()
);

create table if not exists v_personnel (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references v_tenants(id) on delete cascade,
  full_name text not null,
  email text not null,
  role text not null default 'employee',
  status text not null default 'active' check (status in ('active','suspended','revoked')),
  link_identifier text not null unique,
  password_hash text,
  created_at timestamptz not null default now(),
  unique (tenant_id, email)
);

create table if not exists v_worksites (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references v_tenants(id) on delete cascade,
  name text not null,
  latitude double precision not null check (latitude between -90 and 90),
  longitude double precision not null check (longitude between -180 and 180),
  radius_m integer not null default 150 check (radius_m between 25 and 5000),
  active boolean not null default true,
  created_at timestamptz not null default now()
);

create table if not exists v_personnel_assignments (
  personnel_id uuid not null references v_personnel(id) on delete cascade,
  worksite_id uuid not null references v_worksites(id) on delete cascade,
  primary key (personnel_id, worksite_id)
);

create table if not exists v_work_schedules (
  id uuid primary key default gen_random_uuid(),
  personnel_id uuid not null references v_personnel(id) on delete cascade,
  day_of_week smallint not null check (day_of_week between 0 and 6),
  starts_at time not null,
  ends_at time not null,
  timezone text not null default 'America/Port_of_Spain',
  active boolean not null default true
);

create table if not exists v_location_consents (
  personnel_id uuid primary key references v_personnel(id) on delete cascade,
  granted boolean not null default false,
  granted_at timestamptz,
  revoked_at timestamptz,
  user_agent text,
  updated_at timestamptz not null default now()
);

create table if not exists v_location_events (
  id bigserial primary key,
  tenant_id uuid not null references v_tenants(id) on delete cascade,
  personnel_id uuid not null references v_personnel(id) on delete cascade,
  latitude double precision not null check (latitude between -90 and 90),
  longitude double precision not null check (longitude between -180 and 180),
  accuracy_m double precision,
  recorded_at timestamptz not null default now(),
  accepted boolean not null default false,
  decision text not null,
  source text not null default 'velloq-link'
);

create table if not exists v_personnel_latest_location (
  personnel_id uuid primary key references v_personnel(id) on delete cascade,
  tenant_id uuid not null references v_tenants(id) on delete cascade,
  latitude double precision,
  longitude double precision,
  accuracy_m double precision,
  status text not null default 'inactive',
  last_seen_at timestamptz,
  updated_at timestamptz not null default now()
);

create table if not exists v_privacy_audit_log (
  id bigserial primary key,
  tenant_id uuid references v_tenants(id) on delete cascade,
  personnel_id uuid references v_personnel(id) on delete set null,
  event_type text not null,
  detail jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create index if not exists v_location_events_tenant_time_idx on v_location_events (tenant_id, recorded_at desc);
create index if not exists v_location_events_person_time_idx on v_location_events (personnel_id, recorded_at desc);
create index if not exists v_latest_tenant_idx on v_personnel_latest_location (tenant_id, status);

create or replace function v_distance_m(lat1 double precision, lon1 double precision, lat2 double precision, lon2 double precision)
returns double precision language sql immutable as $$
  select 6371000 * 2 * asin(sqrt(
    power(sin(radians(lat2-lat1)/2),2) +
    cos(radians(lat1))*cos(radians(lat2))*power(sin(radians(lon2-lon1)/2),2)
  ));
$$;

alter table v_tenants enable row level security;
alter table v_personnel enable row level security;
alter table v_worksites enable row level security;
alter table v_personnel_assignments enable row level security;
alter table v_work_schedules enable row level security;
alter table v_location_consents enable row level security;
alter table v_location_events enable row level security;
alter table v_personnel_latest_location enable row level security;
alter table v_privacy_audit_log enable row level security;

-- No anonymous direct location reads/writes. The Edge Function is the policy gate.
revoke all on v_location_events from anon, authenticated;
revoke all on v_personnel_latest_location from anon, authenticated;
revoke all on v_privacy_audit_log from anon, authenticated;
