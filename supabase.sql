-- VekterPrep: kjør hele denne filen én gang i Supabase → SQL Editor → Run

create table if not exists public.profiles (
  id uuid primary key references auth.users on delete cascade,
  email text,
  name text not null default '',
  wp text not null default 'kjopesenter',
  sted text not null default '',
  goal text not null default 'eksamen',
  plan text not null default 'gratis' check (plan in ('gratis','pro','livstid')),
  is_admin boolean not null default false,
  created_at timestamptz not null default now()
);
create table if not exists public.progress (
  user_id uuid primary key references auth.users on delete cascade,
  data jsonb not null default '{}'::jsonb,
  upd bigint not null default 0
);
create table if not exists public.invites (
  email text primary key,
  plan text not null default 'pro' check (plan in ('gratis','pro','livstid')),
  created_at timestamptz not null default now()
);

alter table public.profiles enable row level security;
alter table public.progress enable row level security;
alter table public.invites  enable row level security;

create or replace function public.is_admin() returns boolean
language sql stable security definer set search_path = public as
$$ select coalesce((select is_admin from public.profiles where id = auth.uid()), false) $$;

-- Hvem får lese og skrive hva
drop policy if exists profiles_select on public.profiles;
drop policy if exists profiles_update on public.profiles;
drop policy if exists progress_all on public.progress;
drop policy if exists invites_all on public.invites;
create policy profiles_select on public.profiles for select to authenticated using (id = auth.uid() or public.is_admin());
create policy profiles_update on public.profiles for update to authenticated using (id = auth.uid()) with check (id = auth.uid());
create policy progress_all on public.progress for all to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy invites_all on public.invites for all to authenticated using (public.is_admin()) with check (public.is_admin());

-- Brukere kan endre egen profil, men ikke plan eller admin-status
revoke all on public.profiles, public.progress, public.invites from anon, authenticated;
grant select on public.profiles to authenticated;
grant update (name, wp, sted, goal) on public.profiles to authenticated;
grant select, insert, update on public.progress to authenticated;
grant select, insert, update, delete on public.invites to authenticated;

-- Ny bruker får profil automatisk, med plan fra invitasjon hvis e-posten er lagt inn
create or replace function public.handle_new_user() returns trigger
language plpgsql security definer set search_path = public as $$
declare p text;
begin
  select plan into p from public.invites where email = lower(new.email);
  insert into public.profiles (id, email, plan) values (new.id, lower(new.email), coalesce(p, 'gratis'))
  on conflict (id) do nothing;
  delete from public.invites where email = lower(new.email);
  return new;
end $$;
drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created after insert on auth.users
  for each row execute function public.handle_new_user();

-- Bare admin kan endre plan
create or replace function public.admin_set_plan(target uuid, new_plan text) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception 'ikke admin'; end if;
  update public.profiles set plan = new_plan where id = target;
end $$;

revoke execute on function public.handle_new_user() from public, anon, authenticated;
revoke execute on function public.admin_set_plan(uuid, text) from public, anon;
grant execute on function public.admin_set_plan(uuid, text) to authenticated;
grant execute on function public.is_admin() to authenticated;

-- ETTER at du har registrert deg på nettsiden: bytt ut e-posten og kjør denne ene linjen
-- update public.profiles set is_admin = true, plan = 'livstid' where email = 'DIN-EPOST-HER';
