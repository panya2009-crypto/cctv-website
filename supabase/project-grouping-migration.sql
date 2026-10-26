-- Advance Network CCTV: additive project grouping migration
-- Safe to run once in Supabase SQL Editor. Does not delete or move existing image files.
begin;

create table if not exists public.projects (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  description text,
  category text not null default 'CCTV',
  cover_image_path text,
  is_published boolean not null default true,
  display_order integer not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create unique index if not exists projects_name_unique_ci
  on public.projects (lower(name));

alter table public.gallery_images
  add column if not exists project_id uuid references public.projects(id) on delete set null;

-- Create one project for each existing title; do not modify or delete gallery rows.
insert into public.projects (name, category, description, display_order, is_published)
select distinct on (trim(coalesce(title, 'ผลงานติดตั้ง')))
  trim(coalesce(title, 'ผลงานติดตั้ง')),
  coalesce(category, 'CCTV'),
  null,
  0,
  true
from public.gallery_images
where trim(coalesce(title, '')) <> ''
order by trim(coalesce(title, 'ผลงานติดตั้ง')), created_at asc
on conflict do nothing;

-- Link old gallery records to projects by matching their existing title.
update public.gallery_images g
set project_id = p.id
from public.projects p
where g.project_id is null
  and lower(trim(coalesce(g.title, ''))) = lower(trim(p.name));

create index if not exists gallery_images_project_id_idx
  on public.gallery_images (project_id);

alter table public.projects enable row level security;

drop policy if exists "Public can view published projects" on public.projects;
create policy "Public can view published projects"
  on public.projects for select
  using (is_published = true);

drop policy if exists "Admin can manage projects" on public.projects;
create policy "Admin can manage projects"
  on public.projects for all
  using (auth.uid() = '308c8555-b92e-461d-8911-d4c2bef01dfc'::uuid)
  with check (auth.uid() = '308c8555-b92e-461d-8911-d4c2bef01dfc'::uuid);

commit;

-- Verification: expected to return all existing gallery rows and show which rows were linked.
select
  g.id,
  g.title,
  g.image_path,
  g.is_published,
  g.project_id,
  p.name as project_name
from public.gallery_images g
left join public.projects p on p.id = g.project_id
order by g.created_at desc;
