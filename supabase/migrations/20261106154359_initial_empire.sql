-- First playable slice. Alpha defaults are proposals; see docs/rules.md.
create schema if not exists private;
revoke all on schema private from public, anon;
grant usage on schema private to authenticated;

create table public.seasons (
 id uuid primary key default gen_random_uuid(),
 name text not null,
 starts_at timestamptz not null default now(),
 ends_at timestamptz not null,
 status text not null check(status in ('alpha','closed')),
 check(ends_at > starts_at)
);
create unique index seasons_one_alpha on public.seasons(status) where status = 'alpha';
alter table public.seasons enable row level security;
revoke all on public.seasons from anon, authenticated;
grant select on public.seasons to authenticated;
create policy seasons_read on public.seasons for select to authenticated using(true);

create table public.profiles (
 id uuid primary key references auth.users(id) on delete cascade,
 username text not null check(username ~ '^[a-zA-Z0-9_-]{3,24}$'),
 avatar_path text,
 created_at timestamptz not null default now(),
 check(avatar_path is null or avatar_path = id::text || '/avatar.webp')
);
create unique index profiles_username_unique on public.profiles(lower(username));
alter table public.profiles enable row level security;
revoke all on public.profiles from anon, authenticated;
grant select on public.profiles to authenticated;
grant update(avatar_path) on public.profiles to authenticated;
create policy profiles_own_read on public.profiles for select to authenticated using(id = (select auth.uid()));
create policy profiles_own_avatar on public.profiles for update to authenticated
 using(id = (select auth.uid())) with check(id = (select auth.uid()));

create table public.empires (
 id uuid primary key default gen_random_uuid(),
 season_id uuid not null references public.seasons(id),
 player_id uuid not null references public.profiles(id) on delete cascade,
 name text not null check(char_length(name) between 3 and 40),
 treasury bigint not null default 100000 check(treasury >= 0),
 grade text not null default 'Matelot',
 created_at timestamptz not null default now(),
 unique(season_id,player_id)
);
alter table public.empires enable row level security;
revoke all on public.empires from anon, authenticated;
grant select on public.empires to authenticated;
create policy empires_own_read on public.empires for select to authenticated using(player_id = (select auth.uid()));
create index empires_player on public.empires(player_id);

create table public.planets (
 id uuid primary key default gen_random_uuid(),
 serial bigint generated always as identity unique,
 season_id uuid not null references public.seasons(id),
 owner_empire_id uuid references public.empires(id) on delete set null,
 name text,
 race text not null check(race in ('vael','khar','elys')),
 resource text not null check(resource in ('aurite','biomasse','ferros')),
 x double precision not null default random()*1000,
 y double precision not null default random()*1000,
 population bigint not null default 1000000 check(population >= 0),
 civilization integer not null default 1 check(civilization >= 1),
 trade_capacity integer not null default 0 check(trade_capacity between 0 and 200),
 soldiers integer not null default 100 check(soldiers >= 0),
 scouts integer not null default 0 check(scouts >= 0),
 bombers integer not null default 0 check(bombers >= 0),
 fighters integer not null default 0 check(fighters >= 0),
 governance text not null default 'conseil' check(governance in ('conseil','tyrannie')),
 energy integer not null default 0 check(energy >= 0),
 energy_max integer not null default 100 check(energy_max >= energy),
 rename_available boolean not null default false,
 created_at timestamptz not null default now(),
 check(name is null or char_length(name) between 3 and 40)
);
create index planets_owner on public.planets(owner_empire_id);
create index planets_season on public.planets(season_id);
alter table public.planets enable row level security;
revoke all on public.planets from anon, authenticated;
grant select on public.planets to authenticated;
create policy planets_own_read on public.planets for select to authenticated
 using(exists(select 1 from public.empires e where e.id = owner_empire_id and e.player_id = (select auth.uid())));

insert into public.seasons(name,ends_at,status) values ('Session Alpha', now() + interval '1 year','alpha');
insert into public.planets(season_id,race,resource)
 select s.id, (array['vael','khar','elys'])[1+((n-1)%3)], (array['aurite','biomasse','ferros'])[1+((n/3)%3)]
 from public.seasons s cross join generate_series(1,50) n where s.status='alpha';
update public.planets set name = 'Terra_Nullius_' || serial where name is null;

create function private.found_empire(p_username text,p_empire_name text,p_planet_name text)
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
   raise exception 'Confirme ton adresse e-mail avant de créer ton empire.';
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
 if p_empire_name is null or char_length(btrim(p_empire_name)) not between 3 and 40
   or p_planet_name is null or char_length(btrim(p_planet_name)) not between 3 and 40 then
   raise exception 'Choisis des noms de 3 à 40 caractères.';
 end if;
 insert into public.profiles(id,username) values(v_user,p_username) on conflict(id) do nothing;
 insert into public.empires(season_id,player_id,name) values(v_season.id,v_user,btrim(p_empire_name)) returning id into v_empire;
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
revoke all on function private.found_empire(text,text,text) from public, anon;
grant execute on function private.found_empire(text,text,text) to authenticated;
create function public.found_empire(p_username text,p_empire_name text,p_planet_name text)
returns uuid language sql security invoker set search_path = ''
as $$ select private.found_empire(p_username,p_empire_name,p_planet_name); $$;
revoke all on function public.found_empire(text,text,text) from public, anon;
grant execute on function public.found_empire(text,text,text) to authenticated;

insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values('avatars','avatars',false,2097152,array['image/webp']);
create policy avatar_read on storage.objects for select to authenticated
 using(bucket_id='avatars' and name=(select auth.uid())::text || '/avatar.webp');
create policy avatar_insert on storage.objects for insert to authenticated
 with check(bucket_id='avatars' and name=(select auth.uid())::text || '/avatar.webp');
create policy avatar_update on storage.objects for update to authenticated
 using(bucket_id='avatars' and name=(select auth.uid())::text || '/avatar.webp')
 with check(bucket_id='avatars' and name=(select auth.uid())::text || '/avatar.webp');
create policy avatar_delete on storage.objects for delete to authenticated
 using(bucket_id='avatars' and name=(select auth.uid())::text || '/avatar.webp');
