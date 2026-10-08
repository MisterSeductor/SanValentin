-- San Valentín v4: pega en Supabase > SQL Editor > Run (después de schema_v3.sql)

-- BLOQUEOS
create table blocks(
 blocker uuid references profiles on delete cascade,
 blocked uuid references profiles on delete cascade,
 created_at timestamptz default now(),
 primary key(blocker,blocked));
alter table blocks enable row level security;
create policy b_sel on blocks for select to authenticated using(blocker=auth.uid());

-- ¿Alguno de los dos bloqueó al otro? (se salta RLS a propósito para que el bloqueado tampoco vea a quien lo bloqueó)
create function is_blocked(a uuid,b uuid) returns boolean language sql security definer stable set search_path=public as $$
 select exists(select 1 from blocks where (blocker=a and blocked=b) or (blocker=b and blocked=a)) $$;

-- Los perfiles bloqueados (en cualquier dirección) desaparecen
drop policy p_sel on profiles;
create policy p_sel on profiles for select to authenticated using(not is_blocked(id,auth.uid()));

-- Bloquear: registra el bloqueo y cierra el chat entre ambos
create function block_user(target uuid) returns void language plpgsql security definer set search_path=public as $$
begin
 if target=auth.uid() then return; end if;
 insert into blocks(blocker,blocked) values(auth.uid(),target) on conflict do nothing;
 update matches set status='closed' where a in(auth.uid(),target) and b in(auth.uid(),target);
end $$;
revoke execute on function block_user(uuid) from public, anon;
grant execute on function block_user(uuid) to authenticated;

-- BORRAR MI CUENTA (borra perfil, likes, matches y mensajes en cascada)
create function delete_my_account() returns void language sql security definer set search_path=public,auth as $$
 delete from auth.users where id=auth.uid() $$;
revoke execute on function delete_my_account() from public, anon;
grant execute on function delete_my_account() to authenticated;
