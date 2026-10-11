-- San Valentín v7: pega en Supabase > SQL Editor > Run (después de schema_v6.sql)
-- Números ajustables: lote = 10 perfiles, 3 invitaciones enviadas/día, 8 recibidas/día por persona, 12 apariciones/día por perfil, chats se cierran a las 72 h sin mensajes.

alter table profiles
 add column gender text check(gender in ('Mujer','Hombre','No binario')),
 add column seeking text default 'Todos' check(seeking in ('Mujeres','Hombres','Todos'));

-- Día de Ecuador (el lote cambia a medianoche hora local)
create function today_ec() returns date language sql stable as $$ select (now() at time zone 'America/Guayaquil')::date $$;

-- ¿esta persona busca a esa otra? (si falta algún dato, no se bloquea)
create function seeks(s text, g text) returns boolean language sql immutable as $$
 select s is null or s='Todos' or g is null or (s='Mujeres' and g='Mujer') or (s='Hombres' and g='Hombre') $$;

create table invites(
 id bigserial primary key,
 from_id uuid not null references profiles on delete cascade,
 to_id uuid not null references profiles on delete cascade,
 message text not null check(char_length(message) between 5 and 140),
 day date not null default today_ec(),
 status text not null default 'pending' check(status in ('pending','accepted','declined')),
 created_at timestamptz default now(),
 unique(from_id,to_id));
alter table invites enable row level security;
create policy i_sel on invites for select to authenticated using(auth.uid() in (from_id,to_id));
-- sin políticas de escritura: solo se envía y responde con las funciones de abajo

create table daily_batches(
 user_id uuid references profiles on delete cascade,
 day date, profile_id uuid references profiles on delete cascade, pos int,
 primary key(user_id,day,profile_id));
alter table daily_batches enable row level security; -- sin políticas: solo las funciones lo tocan

-- LOTE DEL DÍA: 10 perfiles compatibles, fijos todo el día. Los menos mostrados hoy van primero
-- y nadie aparece en más de 12 lotes al día: así nadie se satura y nadie queda invisible.
create function get_batch(amin int default 18, amax int default 99)
returns table(id uuid,name text,age int,city text,intent text,q1 text,q2 text,q3 text,photo_url text,photos text[],verified boolean,
 height_cm int,weight_kg int,education text,drinks text,smokes text,workout text,personality text,interests text[],last_seen timestamptz,gender text,invited boolean)
language plpgsql security definer set search_path=public as $$
declare d date:=today_ec(); me_row profiles; n int;
begin
 select * into me_row from profiles where profiles.id=auth.uid();
 select count(*) into n from daily_batches b where b.user_id=auth.uid() and b.day=d;
 if n=0 then
  insert into daily_batches(user_id,day,profile_id,pos)
  select auth.uid(), d, y.pid, y.rn from (
   select x.pid, row_number() over(order by x.app, random()) as rn from (
    select p.id as pid,
     (select count(*) from daily_batches b where b.day=d and b.profile_id=p.id) as app
    from profiles p
    where p.id<>auth.uid() and not p.paused and not is_blocked(p.id,auth.uid())
     and p.city=me_row.city and p.age between amin and amax
     and seeks(me_row.seeking,p.gender) and seeks(p.seeking,me_row.gender)
     and not exists(select 1 from invites i where (i.from_id=auth.uid() and i.to_id=p.id) or (i.from_id=p.id and i.to_id=auth.uid() and i.status<>'pending'))
     and not exists(select 1 from matches m where m.a in(auth.uid(),p.id) and m.b in(auth.uid(),p.id))
     and not exists(select 1 from swipes s where s.from_id=auth.uid() and s.to_id=p.id)
     and (select count(*) from daily_batches b where b.day=d and b.profile_id=p.id) < 12
   ) x
  ) y where y.rn<=10;
 end if;
 return query
  select p.id,p.name,p.age,p.city,p.intent,p.q1,p.q2,p.q3,p.photo_url,p.photos,p.verified,
   p.height_cm,p.weight_kg,p.education,p.drinks,p.smokes,p.workout,p.personality,p.interests,p.last_seen,p.gender,
   exists(select 1 from invites i where i.from_id=auth.uid() and i.to_id=p.id)
  from daily_batches b join profiles p on p.id=b.profile_id
  where b.user_id=auth.uid() and b.day=d order by b.pos;
end $$;

-- ENVIAR INVITACIÓN (máx. 3 al día; la otra persona recibe máx. 8 al día). Si ya te había invitado, hay match.
create function send_invite(target uuid, msg text) returns text language plpgsql security definer set search_path=public as $$
declare d date:=today_ec(); sent int; recv int; rev_id bigint; n1 int; n2 int;
begin
 if auth.uid() is null then raise exception 'Inicia sesión'; end if;
 if target=auth.uid() or is_blocked(auth.uid(),target) then raise exception 'Esta persona no está disponible'; end if;
 select count(*) into sent from invites where from_id=auth.uid() and day=d;
 if sent>=3 then raise exception 'Ya usaste tus 3 invitaciones de hoy. Mañana tendrás un lote nuevo.'; end if;
 select count(*) into recv from invites where to_id=target and day=d;
 if recv>=8 then raise exception 'Esta persona ya recibió el máximo de invitaciones de hoy. Elige a alguien más.'; end if;
 select i.id into rev_id from invites i where i.from_id=target and i.to_id=auth.uid() and i.status='pending';
 insert into invites(from_id,to_id,message) values(auth.uid(),target,left(trim(msg),140));
 if rev_id is not null then
  select count(*) into n1 from matches where status='active' and (a=auth.uid() or b=auth.uid());
  select count(*) into n2 from matches where status='active' and (a=target or b=target);
  if n1<5 and n2<5 then
   update invites set status='accepted' where id=rev_id;
   update invites set status='accepted' where from_id=auth.uid() and to_id=target;
   insert into matches(a,b) values(least(auth.uid(),target),greatest(auth.uid(),target)) on conflict do nothing;
   return 'match';
  end if;
 end if;
 return 'sent';
end $$;

-- RESPONDER una invitación recibida
create function respond_invite(inv bigint, accept boolean) returns text language plpgsql security definer set search_path=public as $$
declare r invites; n1 int; n2 int;
begin
 select * into r from invites where id=inv and to_id=auth.uid() and status='pending';
 if not found then raise exception 'Invitación no disponible'; end if;
 if not accept then update invites set status='declined' where id=inv; return 'declined'; end if;
 select count(*) into n1 from matches where status='active' and (a=auth.uid() or b=auth.uid());
 select count(*) into n2 from matches where status='active' and (a=r.from_id or b=r.from_id);
 if n1>=5 then raise exception 'Ya tienes 5 chats activos. Cierra uno para aceptar.'; end if;
 if n2>=5 then raise exception 'Esa persona ya tiene 5 chats activos. Inténtalo más tarde.'; end if;
 update invites set status='accepted' where id=inv;
 insert into matches(a,b) values(least(auth.uid(),r.from_id),greatest(auth.uid(),r.from_id)) on conflict do nothing;
 return 'match';
end $$;

-- Los chats sin ningún mensaje se cierran a las 72 horas (liberan el cupo de 5 chats)
create function expire_my_matches() returns void language sql security definer set search_path=public as $$
 update matches set status='closed'
 where status='active' and auth.uid() in (a,b) and created_at < now()-interval '72 hours'
  and not exists(select 1 from messages m where m.match_id=matches.id) $$;

revoke execute on function get_batch(int,int), send_invite(uuid,text), respond_invite(bigint,boolean), expire_my_matches() from public, anon;
grant execute on function get_batch(int,int), send_invite(uuid,text), respond_invite(bigint,boolean), expire_my_matches() to authenticated;
