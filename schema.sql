-- San Valentín: pega todo esto en Supabase > SQL Editor > Run
create table profiles(
 id uuid primary key references auth.users on delete cascade,
 name text not null, age int check(age>=18), city text not null,
 intent text not null, q1 text, q2 text, q3 text, photo_url text,
 verified boolean default false, created_at timestamptz default now());
create table swipes(
 from_id uuid references profiles on delete cascade,
 to_id uuid references profiles on delete cascade,
 liked boolean not null, created_at timestamptz default now(),
 primary key(from_id,to_id));
create table matches(
 id bigserial primary key,
 a uuid references profiles on delete cascade,
 b uuid references profiles on delete cascade,
 status text default 'active', created_at timestamptz default now(),
 unique(a,b));
create table messages(
 id bigserial primary key,
 match_id bigint references matches on delete cascade,
 sender_id uuid references profiles on delete cascade,
 body text not null check(length(body)<=1000),
 kind text default 'text', created_at timestamptz default now());
create table reports(
 id bigserial primary key, reporter uuid, reported uuid, reason text,
 created_at timestamptz default now());

alter table profiles enable row level security;
alter table swipes enable row level security;
alter table matches enable row level security;
alter table messages enable row level security;
alter table reports enable row level security;

create policy p_sel on profiles for select to authenticated using(true);
create policy p_ins on profiles for insert to authenticated with check(id=auth.uid());
create policy p_upd on profiles for update to authenticated using(id=auth.uid());
create policy s_ins on swipes for insert to authenticated with check(from_id=auth.uid());
create policy s_sel on swipes for select to authenticated using(from_id=auth.uid() or (to_id=auth.uid() and liked));
create policy m_sel on matches for select to authenticated using(auth.uid() in (a,b));
create policy m_upd on matches for update to authenticated using(auth.uid() in (a,b));
create policy g_sel on messages for select to authenticated using(exists(select 1 from matches m where m.id=match_id and auth.uid() in (m.a,m.b)));
create policy g_ins on messages for insert to authenticated with check(sender_id=auth.uid() and exists(select 1 from matches m where m.id=match_id and m.status='active' and auth.uid() in (m.a,m.b)));
create policy r_ins on reports for insert to authenticated with check(reporter=auth.uid());

-- Match automático cuando el like es mutuo (máximo 5 chats activos por persona)
create function make_match() returns trigger language plpgsql security definer as $$
declare n1 int; n2 int;
begin
 if new.liked and exists(select 1 from swipes where from_id=new.to_id and to_id=new.from_id and liked) then
  select count(*) into n1 from matches where status='active' and (a=new.from_id or b=new.from_id);
  select count(*) into n2 from matches where status='active' and (a=new.to_id or b=new.to_id);
  if n1<5 and n2<5 then
   insert into matches(a,b) values(least(new.from_id,new.to_id),greatest(new.from_id,new.to_id)) on conflict do nothing;
  end if;
 end if;
 return new;
end $$;
create trigger t_match after insert on swipes for each row execute function make_match();

-- Tiempo real para el chat
alter publication supabase_realtime add table messages;

-- Fotos
insert into storage.buckets(id,name,public) values('photos','photos',true) on conflict do nothing;
create policy ph_ins on storage.objects for insert to authenticated with check(bucket_id='photos' and (storage.foldername(name))[1]=auth.uid()::text);
create policy ph_sel on storage.objects for select using(bucket_id='photos');
