-- Additive migration: existing accounts, names, worlds and balances are preserved.
alter table public.planets add column clan_tag_visible boolean not null default false;
alter table public.planets add column auto_trade boolean not null default true;

create table public.clans (
 id uuid primary key default gen_random_uuid(),
 season_id uuid not null references public.seasons(id),
 name text not null check(char_length(name) between 3 and 24 and name=btrim(name) and name !~ '[[:cntrl:]\[\]<>]'),
 created_at timestamptz not null default now(),
 unique(id,season_id)
);
create unique index clans_name_unique on public.clans(season_id,lower(name));
alter table public.clans enable row level security;
revoke all on public.clans from anon,authenticated;
grant select on public.clans to authenticated;
create policy clan_directory on public.clans for select to authenticated using(true);

-- No owner/member identity on the public directory. This relation is not exposed.
create table private.clan_memberships (
 empire_id uuid primary key references public.empires(id) on delete cascade,
 clan_id uuid not null,
 season_id uuid not null references public.seasons(id),
 role text not null check(role in ('founder','member')),
 joined_at timestamptz not null default clock_timestamp(),
 foreign key(clan_id,season_id) references public.clans(id,season_id) on delete cascade
);
create index clan_memberships_clan on private.clan_memberships(clan_id);
create index clan_memberships_season on private.clan_memberships(season_id);
create unique index clan_one_founder on private.clan_memberships(clan_id) where role='founder';
alter table private.clan_memberships enable row level security;
revoke all on private.clan_memberships from public,anon,authenticated;

create function private.active_player_id() returns uuid
language plpgsql security definer set search_path='' as $$
declare v_id uuid;
begin
 if auth.uid() is null then raise exception 'Connexion requise.' using errcode='28000'; end if;
 select e.id into v_id from public.empires e join public.seasons s on s.id=e.season_id
 where e.player_id=auth.uid() and s.status='alpha' and now()>=s.starts_at and now()<s.ends_at;
 if v_id is null then raise exception 'Rejoignez une session active avec votre première planète.'; end if;
 return v_id;
end $$;
revoke all on function private.active_player_id() from public,anon,authenticated;

create function private.manage_clan(p_action text,p_clan_id uuid default null,p_name text default null)
returns uuid language plpgsql security definer set search_path='' as $$
declare
 v_player uuid; v_season uuid; v_current private.clan_memberships%rowtype;
 v_clan uuid; v_next uuid; v_name text:=btrim(p_name);
begin
 -- Same lock order as founding; serializes concurrent creates, joins and departures.
 select id into v_season from public.seasons where status='alpha' for update;
 v_player:=private.active_player_id();
 perform 1 from public.empires where id=v_player for update;
 select * into v_current from private.clan_memberships where empire_id=v_player;
 if p_action='create' then
   if v_name is null or char_length(v_name) not between 3 and 24 or v_name ~ '[[:cntrl:]\[\]<>]' then
     raise exception 'Le nom du clan doit contenir 3 à 24 caractères, sans crochets ni caractères de contrôle.';
   end if;
   if v_current.clan_id is not null then
     if exists(select 1 from public.clans where id=v_current.clan_id and lower(name)=lower(v_name)) then return v_current.clan_id; end if;
     raise exception 'Vous appartenez déjà à un clan. Quittez-le avant d’en créer un autre.';
   end if;
   insert into public.clans(season_id,name) values(v_season,v_name) returning id into v_clan;
   insert into private.clan_memberships(empire_id,clan_id,season_id,role) values(v_player,v_clan,v_season,'founder');
   return v_clan;
 elsif p_action='join' then
   if v_current.clan_id=p_clan_id then return p_clan_id; end if;
   if v_current.clan_id is not null then raise exception 'Quittez votre clan actuel avant d’en rejoindre un autre.'; end if;
   select id into v_clan from public.clans where id=p_clan_id and season_id=v_season;
   if v_clan is null then raise exception 'Ce clan n’est plus disponible dans cette session.'; end if;
   insert into private.clan_memberships(empire_id,clan_id,season_id,role) values(v_player,v_clan,v_season,'member');
   return v_clan;
 elsif p_action='leave' then
   -- A stale/retried leave must never remove a newly joined clan.
   if v_current.clan_id is null then return null; end if;
   if p_clan_id is distinct from v_current.clan_id then raise exception 'Votre clan a changé. Actualisez la page.'; end if;
   update public.planets set clan_tag_visible=false where owner_empire_id=v_player;
   delete from private.clan_memberships where empire_id=v_player;
   if v_current.role='founder' then
     select empire_id into v_next from private.clan_memberships where clan_id=v_current.clan_id order by joined_at,empire_id limit 1;
     if v_next is not null then update private.clan_memberships set role='founder' where empire_id=v_next;
     else delete from public.clans where id=v_current.clan_id; end if;
   end if;
   return null;
 else raise exception 'Action de clan inconnue.';
 end if;
exception when unique_violation then raise exception 'Ce nom de clan est déjà utilisé.';
end $$;
revoke all on function private.manage_clan(text,uuid,text) from public,anon;
grant execute on function private.manage_clan(text,uuid,text) to authenticated;
create function public.manage_clan(p_action text,p_clan_id uuid default null,p_name text default null)
returns uuid language sql security invoker set search_path='' as $$select private.manage_clan(p_action,p_clan_id,p_name);$$;
revoke all on function public.manage_clan(text,uuid,text) from public,anon;
grant execute on function public.manage_clan(text,uuid,text) to authenticated;

create function private.my_clan() returns jsonb language plpgsql security definer set search_path='' as $$
declare v_player uuid:=private.active_player_id(); v_result jsonb;
begin
 select jsonb_build_object('id',c.id,'name',c.name,'role',m.role,
   'member_count',(select count(*) from private.clan_memberships other where other.clan_id=c.id))
 into v_result from private.clan_memberships m join public.clans c on c.id=m.clan_id where m.empire_id=v_player;
 return v_result;
end $$;
revoke all on function private.my_clan() from public,anon;
grant execute on function private.my_clan() to authenticated;
create function public.my_clan() returns jsonb language sql security invoker set search_path='' as $$select private.my_clan();$$;
revoke all on function public.my_clan() from public,anon;
grant execute on function public.my_clan() to authenticated;

create function private.set_planet_options(p_planet_id uuid,p_clan_tag_visible boolean,p_auto_trade boolean)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_player uuid; v_season uuid; v_planet public.planets%rowtype;
begin
 select id into v_season from public.seasons where status='alpha' for update;
 v_player:=private.active_player_id();
 if p_clan_tag_visible is null or p_auto_trade is null then raise exception 'Les deux options doivent être précisées.'; end if;
 select * into v_planet from public.planets where id=p_planet_id and owner_empire_id=v_player for update;
 if not found then raise exception 'Planète inaccessible.' using errcode='42501'; end if;
 if p_clan_tag_visible and not exists(select 1 from private.clan_memberships where empire_id=v_player) then
   raise exception 'Rejoignez un clan avant d’afficher son nom.';
 end if;
 update public.planets set clan_tag_visible=p_clan_tag_visible,auto_trade=p_auto_trade where id=p_planet_id;
 return jsonb_build_object('id',p_planet_id,'clan_tag_visible',p_clan_tag_visible,'auto_trade',p_auto_trade);
end $$;
revoke all on function private.set_planet_options(uuid,boolean,boolean) from public,anon;
grant execute on function private.set_planet_options(uuid,boolean,boolean) to authenticated;
create function public.set_planet_options(p_planet_id uuid,p_clan_tag_visible boolean,p_auto_trade boolean)
returns jsonb language sql security invoker set search_path='' as $$select private.set_planet_options(p_planet_id,p_clan_tag_visible,p_auto_trade);$$;
revoke all on function public.set_planet_options(uuid,boolean,boolean) from public,anon;
grant execute on function public.set_planet_options(uuid,boolean,boolean) to authenticated;

-- Allowlisted map projection only. Hidden world names are replaced with signals.
-- No owner ID, clan ID, membership, military, race or resource is returned.
create function private.galaxy_signals()
returns table(id uuid,designation text,x double precision,y double precision,clan_name text,is_own boolean)
language plpgsql security definer set search_path='' as $$
declare v_player uuid:=private.active_player_id(); v_season uuid;
begin
 select e.season_id into v_season from public.empires e where e.id=v_player;
 return query select p.id,
   case when p.owner_empire_id=v_player or (p.clan_tag_visible and c.id is not null) then p.name else 'Signal '||p.serial end,
   p.x,p.y,case when p.clan_tag_visible then c.name else null end,
   coalesce(p.owner_empire_id=v_player,false)
 from public.planets p
 left join private.clan_memberships m on m.empire_id=p.owner_empire_id
 left join public.clans c on c.id=m.clan_id and c.season_id=p.season_id
 where p.season_id=v_season order by p.serial;
end $$;
revoke all on function private.galaxy_signals() from public,anon;
grant execute on function private.galaxy_signals() to authenticated;
create function public.galaxy_signals()
returns table(id uuid,designation text,x double precision,y double precision,clan_name text,is_own boolean)
language sql security invoker set search_path='' as $$select * from private.galaxy_signals();$$;
revoke all on function public.galaxy_signals() from public,anon;
grant execute on function public.galaxy_signals() to authenticated;
-- Keep legacy storage and RPC compatible, but no longer ask or use an empire name.
create or replace function private.found_empire(p_username text,p_empire_name text,p_planet_name text)
returns uuid language plpgsql security definer set search_path = '' as $$
declare
 v_user uuid := auth.uid();
 v_season public.seasons%rowtype;
 v_empire uuid;
 v_planet uuid;
 i integer;
begin
 if v_user is null then raise exception 'Connexion requise.' using errcode='28000'; end if;
 if not exists(select 1 from auth.users where id=v_user and email_confirmed_at is not null) then
   raise exception 'Confirme ton adresse e-mail avant de établir ta première planète.';
 end if;
 -- Lock the season to serialize joins and make creation safe under retries/concurrent requests.
 select * into v_season from public.seasons where status='alpha' for update;
 if not found or now() < v_season.starts_at or now() >= v_season.ends_at then
   raise exception 'La session est fermée.';
 end if;
 select id into v_empire from public.empires where player_id=v_user and season_id=v_season.id;
 if found then return v_empire; end if;
 if p_username is null or p_username !~ '^[a-zA-Z0-9_-]{3,24}$' then
   raise exception 'Le pseudo doit contenir 3 à 24 lettres, chiffres, tirets ou underscores.';
 end if;
 if p_planet_name is null or char_length(btrim(p_planet_name)) not between 3 and 40 then
   raise exception 'Choisis des noms de 3 à 40 caractères.';
 end if;
 insert into public.profiles(id,username) values(v_user,p_username) on conflict(id) do nothing;
 insert into public.empires(season_id,player_id,name) values(v_season.id,v_user,'Participation') returning id into v_empire;
 -- Alpha interpretation: five new worlds INCLUDE the assigned homeworld.
 for i in 1..5 loop
   insert into public.planets(season_id,race,resource,owner_empire_id,name)
    values(v_season.id,(array['vael','khar','elys'])[1+floor(random()*3)::int],
    (array['aurite','biomasse','ferros'])[1+floor(random()*3)::int],
    case when i=1 then v_empire else null end,
    case when i=1 then btrim(p_planet_name) else null end) returning id into v_planet;
   if i<>1 then update public.planets set name='Terra_Nullius_' || serial where id=v_planet; end if;
 end loop;
 return v_empire;
exception when unique_violation then raise exception 'Ce pseudo est déjà utilisé. Choisis-en un autre.';
end;
$$;
create function public.start_player(p_username text,p_planet_name text)
returns uuid language sql security invoker set search_path='' as $$select private.found_empire(p_username,null,p_planet_name);$$;
revoke all on function public.start_player(text,text) from public,anon;
grant execute on function public.start_player(text,text) to authenticated;
