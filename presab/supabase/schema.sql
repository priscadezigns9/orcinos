-- Presab production data foundation
-- Auth is intentionally enabled later. These tables are ready to reference auth.users
-- when the final authentication step is connected.

create extension if not exists pgcrypto;

create type public.presab_role as enum ('administrator', 'teacher');
create type public.attendance_status as enum ('present', 'late', 'absent', 'excused', 'pending');
create type public.notification_channel as enum ('email');
create type public.notification_status as enum ('queued', 'sent', 'delivered', 'failed', 'cancelled');

create table if not exists public.schools (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  code text unique,
  timezone text not null default 'America/Port_of_Spain',
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  school_id uuid references public.schools(id) on delete restrict,
  full_name text not null,
  role public.presab_role not null,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.classes (
  id uuid primary key default gen_random_uuid(),
  school_id uuid not null references public.schools(id) on delete cascade,
  name text not null,
  year_group text,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  unique (school_id, name)
);

create table if not exists public.class_teachers (
  class_id uuid not null references public.classes(id) on delete cascade,
  teacher_id uuid not null references public.profiles(id) on delete cascade,
  primary key (class_id, teacher_id)
);

create table if not exists public.students (
  id uuid primary key default gen_random_uuid(),
  school_id uuid not null references public.schools(id) on delete cascade,
  student_number text not null,
  full_name text not null,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  unique (school_id, student_number)
);

create table if not exists public.class_students (
  class_id uuid not null references public.classes(id) on delete cascade,
  student_id uuid not null references public.students(id) on delete cascade,
  enrolled_from date not null default current_date,
  enrolled_to date,
  primary key (class_id, student_id),
  check (enrolled_to is null or enrolled_to >= enrolled_from)
);

create table if not exists public.parent_contacts (
  id uuid primary key default gen_random_uuid(),
  student_id uuid not null references public.students(id) on delete cascade,
  full_name text not null,
  email text not null,
  email_verified_at timestamptz,
  consent_recorded_at timestamptz,
  consent_source text,
  email_alerts_enabled boolean not null default false,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.attendance_records (
  id uuid primary key default gen_random_uuid(),
  school_id uuid not null references public.schools(id) on delete cascade,
  class_id uuid not null references public.classes(id) on delete restrict,
  student_id uuid not null references public.students(id) on delete restrict,
  attendance_date date not null,
  session_name text not null default 'Morning',
  status public.attendance_status not null default 'pending',
  recorded_at timestamptz,
  recorded_by uuid references public.profiles(id) on delete set null,
  absence_reason text,
  source text not null default 'manual' check (source in ('manual', 'camera', 'import')),
  finalized_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (class_id, student_id, attendance_date, session_name)
);

create table if not exists public.attendance_audit_log (
  id uuid primary key default gen_random_uuid(),
  attendance_id uuid not null references public.attendance_records(id) on delete cascade,
  changed_by uuid references public.profiles(id) on delete set null,
  previous_status public.attendance_status,
  new_status public.attendance_status not null,
  reason text,
  created_at timestamptz not null default now()
);

create table if not exists public.notification_events (
  id uuid primary key default gen_random_uuid(),
  school_id uuid not null references public.schools(id) on delete cascade,
  attendance_id uuid references public.attendance_records(id) on delete set null,
  parent_contact_id uuid not null references public.parent_contacts(id) on delete cascade,
  channel public.notification_channel not null default 'email',
  status public.notification_status not null default 'queued',
  subject text not null,
  body text not null,
  provider_message_id text,
  attempts integer not null default 0,
  last_error text,
  queued_at timestamptz not null default now(),
  sent_at timestamptz,
  delivered_at timestamptz
);

create index if not exists idx_attendance_school_date on public.attendance_records(school_id, attendance_date);
create index if not exists idx_attendance_student_date on public.attendance_records(student_id, attendance_date);
create index if not exists idx_parent_student on public.parent_contacts(student_id);
create index if not exists idx_notifications_status on public.notification_events(status, queued_at);

create or replace function public.set_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists schools_updated_at on public.schools;
create trigger schools_updated_at before update on public.schools for each row execute function public.set_updated_at();
drop trigger if exists profiles_updated_at on public.profiles;
create trigger profiles_updated_at before update on public.profiles for each row execute function public.set_updated_at();
drop trigger if exists parent_contacts_updated_at on public.parent_contacts;
create trigger parent_contacts_updated_at before update on public.parent_contacts for each row execute function public.set_updated_at();
drop trigger if exists attendance_updated_at on public.attendance_records;
create trigger attendance_updated_at before update on public.attendance_records for each row execute function public.set_updated_at();

-- RLS and policies are added after Supabase Auth is connected, so the schema
-- can be tested safely without accidentally blocking the current demo.
