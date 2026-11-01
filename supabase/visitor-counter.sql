-- Advance Network website visitor counter
-- Run once in Supabase Dashboard > SQL Editor > New query.

create table if not exists public.website_visit_total (
  id boolean primary key default true check (id = true),
  total bigint not null default 0
);
insert into public.website_visit_total (id, total)
values (true, 0)
on conflict (id) do nothing;

create table if not exists public.website_visit_daily (
  visit_date date primary key,
  total bigint not null default 0
);

alter table public.website_visit_total enable row level security;
alter table public.website_visit_daily enable row level security;

create or replace function public.increment_website_visitors()
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  thai_today date := (now() at time zone 'Asia/Bangkok')::date;
begin
  insert into public.website_visit_total (id, total)
  values (true, 1)
  on conflict (id) do update
    set total = public.website_visit_total.total + 1;

  insert into public.website_visit_daily (visit_date, total)
  values (thai_today, 1)
  on conflict (visit_date) do update
    set total = public.website_visit_daily.total + 1;
end;
$$;

create or replace function public.get_website_visitor_stats()
returns jsonb
language sql
security definer
set search_path = ''
as $$
  select jsonb_build_object(
    'total', coalesce((select total from public.website_visit_total where id = true), 0),
    'today', coalesce((select total from public.website_visit_daily
                       where visit_date = (now() at time zone 'Asia/Bangkok')::date), 0)
  );
$$;

revoke all on public.website_visit_total from anon, authenticated;
revoke all on public.website_visit_daily from anon, authenticated;
revoke all on function public.increment_website_visitors() from public;
revoke all on function public.get_website_visitor_stats() from public;
grant execute on function public.increment_website_visitors() to anon, authenticated;
grant execute on function public.get_website_visitor_stats() to anon, authenticated;
