-- Advance Network CCTV Secondhand Store
-- Run this file in Supabase SQL Editor. Never put the service_role key in website code.

create extension if not exists pgcrypto;

create table if not exists public.store_admins (
  user_id uuid primary key references auth.users(id) on delete cascade,
  created_at timestamptz not null default now()
);

create or replace function public.is_store_admin()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.store_admins
    where user_id = auth.uid()
  );
$$;

grant execute on function public.is_store_admin() to anon, authenticated;

create table if not exists public.used_products (
  id uuid primary key default gen_random_uuid(),
  sku text unique,
  name text not null,
  category text not null,
  brand text,
  model text,
  description text,
  condition_label text not null default 'มือสอง',
  warranty_label text,
  price numeric(12,2) not null check (price >= 0),
  stock_qty integer not null default 1 check (stock_qty >= 0),
  cover_image text,
  is_featured boolean not null default false,
  is_published boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.used_orders (
  id uuid primary key default gen_random_uuid(),
  order_code text not null unique,
  customer_name text not null,
  phone text not null,
  email text,
  shipping_address text not null,
  shipping_method text not null default 'parcel'
    check (shipping_method in ('parcel','pickup')),
  customer_note text,
  subtotal numeric(12,2) not null default 0,
  shipping_fee numeric(12,2) not null default 0,
  total_amount numeric(12,2) not null default 0,
  status text not null default 'pending_payment'
    check (status in ('pending_payment','payment_review','paid','preparing','shipped','completed','cancelled')),
  payment_status text not null default 'awaiting_transfer'
    check (payment_status in ('awaiting_transfer','proof_submitted','verified','rejected','refunded')),
  tracking_number text,
  admin_note text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.used_order_items (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null references public.used_orders(id) on delete cascade,
  product_id uuid references public.used_products(id) on delete set null,
  product_name text not null,
  product_sku text,
  unit_price numeric(12,2) not null check (unit_price >= 0),
  quantity integer not null check (quantity > 0),
  line_total numeric(12,2) not null check (line_total >= 0),
  created_at timestamptz not null default now()
);

create index if not exists used_products_public_idx
  on public.used_products (is_published, category, created_at desc);
create index if not exists used_orders_created_idx
  on public.used_orders (created_at desc);
create index if not exists used_order_items_order_idx
  on public.used_order_items (order_id);

create or replace function public.set_used_store_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists used_products_updated_at on public.used_products;
create trigger used_products_updated_at before update on public.used_products
for each row execute function public.set_used_store_updated_at();

drop trigger if exists used_orders_updated_at on public.used_orders;
create trigger used_orders_updated_at before update on public.used_orders
for each row execute function public.set_used_store_updated_at();

alter table public.store_admins enable row level security;
alter table public.used_products enable row level security;
alter table public.used_orders enable row level security;
alter table public.used_order_items enable row level security;

drop policy if exists "Store admins can read own admin record" on public.store_admins;
create policy "Store admins can read own admin record"
on public.store_admins for select to authenticated
using (user_id = auth.uid());

drop policy if exists "Public can view published used products" on public.used_products;
create policy "Public can view published used products"
on public.used_products for select to anon, authenticated
using (is_published = true or public.is_store_admin());

drop policy if exists "Store admins manage used products" on public.used_products;
create policy "Store admins manage used products"
on public.used_products for all to authenticated
using (public.is_store_admin())
with check (public.is_store_admin());

drop policy if exists "Store admins view used orders" on public.used_orders;
create policy "Store admins view used orders"
on public.used_orders for select to authenticated
using (public.is_store_admin());

drop policy if exists "Store admins update used orders" on public.used_orders;
create policy "Store admins update used orders"
on public.used_orders for update to authenticated
using (public.is_store_admin())
with check (public.is_store_admin());

drop policy if exists "Store admins view order items" on public.used_order_items;
create policy "Store admins view order items"
on public.used_order_items for select to authenticated
using (public.is_store_admin());

grant select on public.used_products to anon, authenticated;
grant insert, update, delete on public.used_products to authenticated;
grant select, update on public.used_orders to authenticated;
grant select on public.used_order_items to authenticated;

-- Public checkout uses this RPC so stock decrement and order creation are atomic.
create or replace function public.create_used_order(
  p_customer_name text,
  p_phone text,
  p_email text,
  p_shipping_address text,
  p_shipping_method text,
  p_customer_note text,
  p_items jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_order_id uuid;
  v_order_code text;
  v_item jsonb;
  v_product public.used_products%rowtype;
  v_qty integer;
  v_subtotal numeric(12,2) := 0;
  v_shipping_fee numeric(12,2) := 0;
  v_total numeric(12,2);
begin
  if length(trim(coalesce(p_customer_name,''))) < 2 then
    raise exception 'กรุณากรอกชื่อผู้สั่งซื้อ';
  end if;
  if length(regexp_replace(coalesce(p_phone,''), '[^0-9]', '', 'g')) < 9 then
    raise exception 'กรุณาตรวจสอบเบอร์โทรศัพท์';
  end if;
  if length(trim(coalesce(p_shipping_address,''))) < 8 then
    raise exception 'กรุณากรอกที่อยู่หรือรายละเอียดการรับสินค้า';
  end if;
  if p_shipping_method not in ('parcel','pickup') then
    raise exception 'วิธีรับสินค้าไม่ถูกต้อง';
  end if;
  if jsonb_typeof(p_items) <> 'array' or jsonb_array_length(p_items) = 0 then
    raise exception 'ไม่มีสินค้าในคำสั่งซื้อ';
  end if;

  v_order_code := 'AN2H-' || to_char(now() at time zone 'Asia/Bangkok','YYYYMMDD')
    || '-' || upper(substr(replace(gen_random_uuid()::text,'-',''),1,6));

  insert into public.used_orders (
    order_code, customer_name, phone, email, shipping_address,
    shipping_method, customer_note, subtotal, shipping_fee, total_amount
  ) values (
    v_order_code, trim(p_customer_name), trim(p_phone), nullif(trim(coalesce(p_email,'')),''),
    trim(p_shipping_address), p_shipping_method, nullif(trim(coalesce(p_customer_note,'')),''),
    0, v_shipping_fee, 0
  ) returning id into v_order_id;

  for v_item in select value from jsonb_array_elements(p_items)
  loop
    v_qty := (v_item->>'quantity')::integer;
    if v_qty < 1 or v_qty > 20 then
      raise exception 'จำนวนสินค้าต่อรายการไม่ถูกต้อง';
    end if;

    select * into v_product
    from public.used_products
    where id = (v_item->>'product_id')::uuid
      and is_published = true
    for update;

    if not found then
      raise exception 'มีสินค้าบางรายการไม่พร้อมจำหน่าย กรุณาตรวจสอบตะกร้าอีกครั้ง';
    end if;
    if v_product.stock_qty < v_qty then
      raise exception 'สินค้า % คงเหลือไม่เพียงพอ', v_product.name;
    end if;

    update public.used_products
    set stock_qty = stock_qty - v_qty
    where id = v_product.id;

    insert into public.used_order_items (
      order_id, product_id, product_name, product_sku, unit_price, quantity, line_total
    ) values (
      v_order_id, v_product.id, v_product.name, v_product.sku,
      v_product.price, v_qty, v_product.price * v_qty
    );

    v_subtotal := v_subtotal + (v_product.price * v_qty);
  end loop;

  v_total := v_subtotal + v_shipping_fee;
  update public.used_orders
  set subtotal = v_subtotal, shipping_fee = v_shipping_fee, total_amount = v_total
  where id = v_order_id;

  return jsonb_build_object(
    'order_id', v_order_id,
    'order_code', v_order_code,
    'subtotal', v_subtotal,
    'shipping_fee', v_shipping_fee,
    'total_amount', v_total
  );
end;
$$;

revoke all on function public.create_used_order(text,text,text,text,text,text,jsonb) from public;
grant execute on function public.create_used_order(text,text,text,text,text,text,jsonb) to anon, authenticated;

-- Public read access to product photos; only store admins can upload/change/delete.
insert into storage.buckets (id, name, public)
values ('used-products', 'used-products', true)
on conflict (id) do update set public = true;

drop policy if exists "Public can view used product images" on storage.objects;
create policy "Public can view used product images"
on storage.objects for select
using (bucket_id = 'used-products');

drop policy if exists "Store admins upload used product images" on storage.objects;
create policy "Store admins upload used product images"
on storage.objects for insert to authenticated
with check (bucket_id = 'used-products' and public.is_store_admin());

drop policy if exists "Store admins update used product images" on storage.objects;
create policy "Store admins update used product images"
on storage.objects for update to authenticated
using (bucket_id = 'used-products' and public.is_store_admin())
with check (bucket_id = 'used-products' and public.is_store_admin());

drop policy if exists "Store admins delete used product images" on storage.objects;
create policy "Store admins delete used product images"
on storage.objects for delete to authenticated
using (bucket_id = 'used-products' and public.is_store_admin());

-- After creating your admin user in Supabase Auth, run:
-- insert into public.store_admins(user_id)
-- select id from auth.users where email = 'YOUR_ADMIN_EMAIL';
