-- Advance Network CCTV: warranty database setup
create table if not exists public.warranties (
  id uuid primary key default gen_random_uuid(),
  warranty_code text not null unique,
  customer_name text not null,
  phone text not null,
  address text,
  job_type text not null default 'CCTV',
  job_description text,
  product_brand text,
  product_model text,
  serial_numbers text,
  quantity integer,
  purchase_date date,
  installation_date date,
  product_warranty_start date,
  product_warranty_end date,
  installation_warranty_start date,
  installation_warranty_end date,
  terms text,
  internal_notes text,
  status text not null default 'active' check (status in ('active','expired','cancelled','pending')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists warranties_code_idx on public.warranties (warranty_code);
create index if not exists warranties_phone_idx on public.warranties (phone);
alter table public.warranties enable row level security;
revoke all on public.warranties from anon, authenticated;
grant select, insert, update, delete on public.warranties to authenticated;
drop policy if exists "Warranty admin full access" on public.warranties;
create policy "Warranty admin full access" on public.warranties
for all to authenticated using (true) with check (true);

-- Public lookup RPC returns customer-safe warranty details and supports exact Serial Number search.
create or replace function public.lookup_warranty(
  p_code text default null,
  p_phone text default null,
  p_serial text default null
)
returns table (
  warranty_code text, customer_name text, job_type text, job_description text,
  product_brand text, product_model text, serial_numbers text, quantity integer,
  product_warranty_start date, product_warranty_end date,
  installation_warranty_start date, installation_warranty_end date,
  status text, terms text
)
language sql security definer set search_path = public
as $$
  select w.warranty_code, w.customer_name, w.job_type, w.job_description,
         w.product_brand, w.product_model, w.serial_numbers, w.quantity,
         w.product_warranty_start, w.product_warranty_end,
         w.installation_warranty_start, w.installation_warranty_end,
         case
           when w.status = 'cancelled' then 'cancelled'
           when w.status = 'pending' then 'pending'
           when (w.product_warranty_end is not null and w.product_warranty_end >= current_date)
             or (w.installation_warranty_end is not null and w.installation_warranty_end >= current_date)
             then 'active'
           else 'expired'
         end, w.terms
  from public.warranties w
  where (nullif(trim(p_code),'') is not null and upper(w.warranty_code)=upper(trim(p_code)))
     or (nullif(trim(p_phone),'') is not null and regexp_replace(w.phone,'\\D','','g')=regexp_replace(trim(p_phone),'\\D','','g'))
     or (nullif(trim(p_serial),'') is not null and exists (
       select 1 from unnest(string_to_array(coalesce(w.serial_numbers,''), E'\\n')) as sn(value)
       where upper(trim(sn.value))=upper(trim(p_serial))
     ))
  order by w.created_at desc
  limit 10;
$$;
revoke all on function public.lookup_warranty(text,text,text) from public;
grant execute on function public.lookup_warranty(text,text,text) to anon, authenticated;
