-- Fix API grants for project grouping. This does not modify or delete gallery data.
GRANT SELECT ON TABLE public.projects TO anon;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.projects TO authenticated;

-- Keep public visitors limited to published projects; admin policy remains enforced by RLS.
ALTER TABLE public.projects ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Public can view published projects" ON public.projects;
CREATE POLICY "Public can view published projects"
  ON public.projects
  FOR SELECT
  TO anon, authenticated
  USING (is_published = true);

DROP POLICY IF EXISTS "Admin can manage projects" ON public.projects;
CREATE POLICY "Admin can manage projects"
  ON public.projects
  FOR ALL
  TO authenticated
  USING (auth.uid() = '308c8555-b92e-461d-8911-d4c2bef01dfc'::uuid)
  WITH CHECK (auth.uid() = '308c8555-b92e-461d-8911-d4c2bef01dfc'::uuid);

-- Verify project table access and current project/image counts.
SELECT
  (SELECT COUNT(*) FROM public.projects) AS total_projects,
  (SELECT COUNT(*) FROM public.gallery_images) AS total_images,
  (SELECT COUNT(*) FROM public.gallery_images WHERE project_id IS NOT NULL) AS linked_images;
