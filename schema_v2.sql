-- San Valentín v2: pega esto en Supabase > SQL Editor > Run (DESPUÉS de schema.sql)
-- Las ciudades se escriben en minúsculas, igual que en los perfiles (ej: 'quito').

create table venues(
 id bigserial primary key, name text not null, category text, city text not null,
 address text, offer text, partner boolean default false, active boolean default true,
 created_at timestamptz default now());
create table events(
 id bigserial primary key, title text not null, description text,
 venue_id bigint references venues, city text not null, starts_at timestamptz not null,
 sponsor text, active boolean default true);
create table ads(
 id bigserial primary key, city text not null, title text not null,
 body text, link text, active boolean default true);

alter table messages add column venue_id bigint references venues;

alter table venues enable row level security;
alter table events enable row level security;
alter table ads enable row level security;
create policy v_sel on venues for select to authenticated using(active);
create policy e_sel on events for select to authenticated using(active);
create policy a_sel on ads for select to authenticated using(active);
-- (Solo tú, desde el panel de Supabase, puedes agregar/editar locales, eventos y anuncios)

-- Métricas para mostrarle a cada local cuántos planes se propusieron en su lugar
create view venue_stats as
 select v.id, v.name, date_trunc('month',m.created_at) as mes, count(*) as planes
 from messages m join venues v on v.id=m.venue_id
 where m.kind='plan' group by 1,2,3;
revoke all on venue_stats from anon, authenticated;

-- Ejemplos (descomenta y cambia por tus datos reales):
-- insert into venues(name,category,city,address,offer,partner) values('Café Luna','Café','tuciudad','Calle 1 y 2','10% de descuento con San Valentín',true);
-- insert into events(title,description,city,starts_at,sponsor) values('Noche de juegos','Trae a alguien nuevo','tuciudad','2026-11-14 19:00-05','Café Luna');
-- insert into ads(city,title,body,link) values('tuciudad','Tu local aquí','Anuncio local','https://ejemplo.com');
