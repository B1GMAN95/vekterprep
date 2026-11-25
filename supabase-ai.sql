-- VekterPrep: teller AI-bruk per bruker per dag. Kjør én gang i Supabase → SQL Editor.
create table if not exists public.ai_usage (
  user_id uuid not null references auth.users on delete cascade,
  day date not null default current_date,
  n int not null default 0,
  primary key (user_id, day)
);
alter table public.ai_usage enable row level security;
revoke all on public.ai_usage from anon, authenticated;

create or replace function public.ai_tick() returns int
language plpgsql security definer set search_path = public as $$
declare c int;
begin
  if auth.uid() is null then raise exception 'ikke innlogget'; end if;
  insert into public.ai_usage (user_id, day, n) values (auth.uid(), current_date, 1)
  on conflict (user_id, day) do update set n = public.ai_usage.n + 1
  returning n into c;
  return c;
end $$;
revoke execute on function public.ai_tick() from public, anon;
grant execute on function public.ai_tick() to authenticated;
