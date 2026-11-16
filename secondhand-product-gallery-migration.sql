-- Run once in Supabase SQL Editor to support up to 5 product images
alter table public.used_products
add column if not exists gallery_images jsonb not null default '[]'::jsonb;

-- Preserve existing cover photos as the first gallery image.
update public.used_products
set gallery_images = jsonb_build_array(cover_image)
where cover_image is not null
  and (gallery_images is null or gallery_images = '[]'::jsonb);
