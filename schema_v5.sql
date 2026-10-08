-- San Valentín v5: pega en Supabase > SQL Editor > Run (después de schema_v4.sql)

-- 1) PERFIL AMPLIADO
alter table profiles
 add column height_cm int check(height_cm is null or height_cm between 120 and 230),
 add column education text, add column drinks text, add column smokes text,
 add column workout text, add column personality text,
 add column interests text[] default '{}';

-- 2) UBICACIÓN APROXIMADA (tabla privada: solo tú ves tu fila; los demás nunca ven coordenadas)
create table locations(
 user_id uuid primary key references profiles on delete cascade,
 lat double precision not null, lng double precision not null,
 updated_at timestamptz default now());
alter table locations enable row level security;
create policy l_all on locations for all to authenticated using(user_id=auth.uid()) with check(user_id=auth.uid());

-- 3) VERIFICACIÓN POR SELFIE
create table verifications(
 user_id uuid primary key references profiles on delete cascade,
 selfie_path text not null, pose text, status text default 'pending',
 created_at timestamptz default now());
alter table verifications enable row level security;
create policy vf_sel on verifications for select to authenticated using(user_id=auth.uid());
create policy vf_ins on verifications for insert to authenticated with check(user_id=auth.uid());
create policy vf_del on verifications for delete to authenticated using(user_id=auth.uid());
insert into storage.buckets(id,name,public) values('selfies','selfies',false) on conflict do nothing;
create policy sf_ins on storage.objects for insert to authenticated with check(bucket_id='selfies' and (storage.foldername(name))[1]=auth.uid()::text);
create policy sf_sel on storage.objects for select to authenticated using(bucket_id='selfies' and (storage.foldername(name))[1]=auth.uid()::text);
create policy sf_del on storage.objects for delete to authenticated using(bucket_id='selfies' and (storage.foldername(name))[1]=auth.uid()::text);

-- Nadie puede ponerse la insignia "verificado" por su cuenta (solo tú, desde el panel de Supabase)
create function protect_verified() returns trigger language plpgsql as $$
begin
 if auth.uid() is not null then
  if tg_op='INSERT' then new.verified:=false; else new.verified:=old.verified; end if;
 end if;
 return new;
end $$;
create trigger t_protect before insert or update on profiles for each row execute function protect_verified();

-- 4) DESCUBRIR con filtros de edad, distancia y lo que busca. Devuelve rangos de distancia, nunca coordenadas.
create function next_profile(max_km int default null, amin int default 18, amax int default 99, want text default null)
returns table(id uuid,name text,age int,city text,intent text,q1 text,q2 text,q3 text,photo_url text,photos text[],verified boolean,
 height_cm int,education text,drinks text,smokes text,workout text,personality text,interests text[],km_band text)
language sql security definer stable set search_path=public as $$
 with me as (select p.city as city, l.lat as lat, l.lng as lng from profiles p left join locations l on l.user_id=p.id where p.id=auth.uid()),
 c as (
  select p.*, me.city as mycity,
   case when me.lat is not null and l.lat is not null then
    6371*acos(least(1,greatest(-1,sin(radians(me.lat))*sin(radians(l.lat))+cos(radians(me.lat))*cos(radians(l.lat))*cos(radians(l.lng-me.lng))))) end as d
  from profiles p cross join me left join locations l on l.user_id=p.id
  where p.id<>auth.uid() and not is_blocked(p.id,auth.uid())
   and p.age between amin and amax and (want is null or p.intent=want)
   and not exists(select 1 from swipes s where s.from_id=auth.uid() and s.to_id=p.id))
 select c.id,c.name,c.age,c.city,c.intent,c.q1,c.q2,c.q3,c.photo_url,c.photos,c.verified,
  c.height_cm,c.education,c.drinks,c.smokes,c.workout,c.personality,c.interests,
  case when c.d is null then null when c.d<1 then 'a menos de 1 km' when c.d<=5 then 'a menos de 5 km'
   when c.d<=10 then 'a menos de 10 km' when c.d<=25 then 'a menos de 25 km' else 'a más de 25 km' end
 from c
 where (max_km is null and c.city=c.mycity) or (max_km is not null and c.d is not null and c.d<=max_km)
 order by c.d nulls last, c.created_at desc limit 1 $$;
revoke execute on function next_profile(int,int,int,text) from public, anon;
grant execute on function next_profile(int,int,int,text) to authenticated;

-- PARA APROBAR UNA SELFIE (a mano, desde SQL Editor): revisa la foto en Storage > selfies y luego:
-- update profiles set verified=true where id='ID-DE-LA-PERSONA';
-- update verifications set status='approved' where user_id='ID-DE-LA-PERSONA';
