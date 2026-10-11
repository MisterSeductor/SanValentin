-- San Valentín v6: pega en Supabase > SQL Editor > Run (después de schema_v5.sql)

alter table profiles
 add column weight_kg int check(weight_kg is null or weight_kg between 35 and 200),
 add column paused boolean default false,
 add column last_seen timestamptz default now();

-- FAVORITOS entre las personas a las que les gustas
create table favorites(
 user_id uuid references profiles on delete cascade,
 fav_id uuid references profiles on delete cascade,
 created_at timestamptz default now(),
 primary key(user_id,fav_id));
alter table favorites enable row level security;
create policy fv_all on favorites for all to authenticated using(user_id=auth.uid()) with check(user_id=auth.uid());

-- DESHACER un "pasar" y cambiar de opinión (pasar -> me gusta)
create policy s_upd on swipes for update to authenticated using(from_id=auth.uid()) with check(from_id=auth.uid());
create policy s_del on swipes for delete to authenticated using(from_id=auth.uid() and liked=false);
drop trigger t_match on swipes;
create trigger t_match after insert or update on swipes for each row execute function make_match();

-- DESCUBRIR actualizado: oculta perfiles pausados y devuelve peso (si lo hicieron público) y última actividad
drop function next_profile(int,int,int,text);
create function next_profile(max_km int default null, amin int default 18, amax int default 99, want text default null)
returns table(id uuid,name text,age int,city text,intent text,q1 text,q2 text,q3 text,photo_url text,photos text[],verified boolean,
 height_cm int,weight_kg int,education text,drinks text,smokes text,workout text,personality text,interests text[],last_seen timestamptz,km_band text)
language sql security definer stable set search_path=public as $$
 with me as (select p.city as city, l.lat as lat, l.lng as lng from profiles p left join locations l on l.user_id=p.id where p.id=auth.uid()),
 c as (
  select p.*, me.city as mycity,
   case when me.lat is not null and l.lat is not null then
    6371*acos(least(1,greatest(-1,sin(radians(me.lat))*sin(radians(l.lat))+cos(radians(me.lat))*cos(radians(l.lat))*cos(radians(l.lng-me.lng))))) end as d
  from profiles p cross join me left join locations l on l.user_id=p.id
  where p.id<>auth.uid() and not p.paused and not is_blocked(p.id,auth.uid())
   and p.age between amin and amax and (want is null or p.intent=want)
   and not exists(select 1 from swipes s where s.from_id=auth.uid() and s.to_id=p.id))
 select c.id,c.name,c.age,c.city,c.intent,c.q1,c.q2,c.q3,c.photo_url,c.photos,c.verified,
  c.height_cm,c.weight_kg,c.education,c.drinks,c.smokes,c.workout,c.personality,c.interests,c.last_seen,
  case when c.d is null then null when c.d<1 then 'a menos de 1 km' when c.d<=5 then 'a menos de 5 km'
   when c.d<=10 then 'a menos de 10 km' when c.d<=25 then 'a menos de 25 km' else 'a más de 25 km' end
 from c
 where (max_km is null and c.city=c.mycity) or (max_km is not null and c.d is not null and c.d<=max_km)
 order by c.d nulls last, c.created_at desc limit 1 $$;
revoke execute on function next_profile(int,int,int,text) from public, anon;
grant execute on function next_profile(int,int,int,text) to authenticated;
