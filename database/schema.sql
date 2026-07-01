-- ASHA AI - Full Database Schema
-- Run this in your Supabase SQL editor

-- ─────────────────────────────────────────────
-- 1. PROFILES TABLE
-- ─────────────────────────────────────────────
create table if not exists public.profiles (
  id uuid primary key default gen_random_uuid(),
  auth_id uuid not null unique references auth.users(id) on delete cascade,
  role text not null check (role in ('user', 'asha_worker', 'ngo_partner')),
  full_name text,
  phone text,
  village text,
  district text,
  age integer,
  is_pregnant boolean default false,
  asha_worker_id uuid references public.profiles(id) on delete set null,
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);

-- ─────────────────────────────────────────────
-- 2. WOMEN TABLE
-- ─────────────────────────────────────────────
create table if not exists public.women (
  id uuid primary key default gen_random_uuid(),
  asha_worker_id uuid not null references public.profiles(id) on delete cascade,
  profile_id uuid references public.profiles(id) on delete set null,
  full_name text not null,
  age integer,
  village text,
  phone text,
  is_pregnant boolean default false,
  pregnancy_months integer,
  last_interaction timestamptz default now(),
  status text default 'active' check (status in ('active', 'pending', 'inactive')),
  notes text,
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);

-- ─────────────────────────────────────────────
-- 3. UPDATED_AT TRIGGER
-- ─────────────────────────────────────────────
create or replace function public.handle_updated_at()
returns trigger as $$
begin
  new.updated_at = now();
  return new;
end;
$$ language plpgsql;

drop trigger if exists profiles_updated_at on public.profiles;
create trigger profiles_updated_at
  before update on public.profiles
  for each row execute procedure public.handle_updated_at();

drop trigger if exists women_updated_at on public.women;
create trigger women_updated_at
  before update on public.women
  for each row execute procedure public.handle_updated_at();

-- ─────────────────────────────────────────────
-- 4. ROW LEVEL SECURITY
-- ─────────────────────────────────────────────
alter table public.profiles enable row level security;
alter table public.women enable row level security;

-- Helper function to get user role without policy recursion
create or replace function public.get_user_role(user_id uuid)
returns text as $$
  select role from public.profiles where auth_id = user_id;
$$ language sql security definer;

-- Profiles: users can read their own, ASHA workers can read their linked users
drop policy if exists "profiles_select" on public.profiles;
create policy "profiles_select" on public.profiles
  for select using (
    auth.uid() = auth_id
    or public.get_user_role(auth.uid()) in ('asha_worker', 'ngo_partner')
  );

drop policy if exists "profiles_insert" on public.profiles;
create policy "profiles_insert" on public.profiles
  for insert with check (auth.uid() = auth_id);

drop policy if exists "profiles_update" on public.profiles;
create policy "profiles_update" on public.profiles
  for update using (auth.uid() = auth_id);

-- Women: ASHA workers can CRUD their own women; NGO can read all
drop policy if exists "women_select" on public.women;
create policy "women_select" on public.women
  for select using (
    exists (
      select 1 from public.profiles p
      where p.auth_id = auth.uid()
      and (
        p.id = women.asha_worker_id
        or p.role = 'ngo_partner'
      )
    )
  );

drop policy if exists "women_insert" on public.women;
create policy "women_insert" on public.women
  for insert with check (
    exists (
      select 1 from public.profiles p
      where p.auth_id = auth.uid() and p.id = women.asha_worker_id
    )
  );

drop policy if exists "women_update" on public.women;
create policy "women_update" on public.women
  for update using (
    exists (
      select 1 from public.profiles p
      where p.auth_id = auth.uid() and p.id = women.asha_worker_id
    )
  );

drop policy if exists "women_delete" on public.women;
create policy "women_delete" on public.women
  for delete using (
    exists (
      select 1 from public.profiles p
      where p.auth_id = auth.uid() and p.id = women.asha_worker_id
    )
  );

-- ─────────────────────────────────────────────
-- 5. SAMPLE DATA (optional - for testing)
-- ─────────────────────────────────────────────
-- After inserting real auth users, you can add womens:
-- insert into public.women (asha_worker_id, full_name, age, village, is_pregnant, pregnancy_months)
-- values ('your-asha-worker-profile-id', 'Sunita Devi', 24, 'Sitapur', true, 6);
