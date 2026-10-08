-- San Valentín v3: pega en Supabase > SQL Editor > Run
alter table profiles add column if not exists photos text[] default '{}';

-- Permite que cada persona borre sus propias fotos del almacenamiento
create policy ph_del on storage.objects for delete to authenticated
 using(bucket_id='photos' and (storage.foldername(name))[1]=auth.uid()::text);
