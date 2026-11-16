-- Run once in Supabase SQL Editor to add structured product specification rows
alter table public.used_products
add column if not exists specifications jsonb not null default '[]'::jsonb;
