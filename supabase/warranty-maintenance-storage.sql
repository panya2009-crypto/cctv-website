-- Allow authenticated warranty admins to upload/remove PDF files only
-- inside the warranty-maintenance/ folder of the existing public portfolio-images bucket.
-- Run once in Supabase SQL Editor if the Admin upload reports a Storage permission error.

do $$
begin
  if not exists (
    select 1 from pg_policies
    where schemaname='storage' and tablename='objects'
      and policyname='Warranty admin upload maintenance PDFs'
  ) then
    execute $policy$
      create policy "Warranty admin upload maintenance PDFs"
      on storage.objects
      for insert
      to authenticated
      with check (
        bucket_id = 'portfolio-images'
        and name like 'warranty-maintenance/%'
      )
    $policy$;
  end if;

  if not exists (
    select 1 from pg_policies
    where schemaname='storage' and tablename='objects'
      and policyname='Warranty admin delete maintenance PDFs'
  ) then
    execute $policy$
      create policy "Warranty admin delete maintenance PDFs"
      on storage.objects
      for delete
      to authenticated
      using (
        bucket_id = 'portfolio-images'
        and name like 'warranty-maintenance/%'
      )
    $policy$;
  end if;
end
$$;
