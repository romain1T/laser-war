-- Joining now creates a request; existing clan memberships remain intact.
create table private.clan_requests(
 id uuid primary key default gen_random_uuid(),empire_id uuid not null references public.empires(id) on delete cascade,
 clan_id uuid not null,season_id uuid not null references public.seasons(id),
 status text not null default 'pending' check(status in ('pending','accepted','declined','cancelled')),
 requested_at timestamptz not null default now(),reviewed_at timestamptz,
 foreign key(clan_id,season_id) references public.clans(id,season_id) on delete cascade
);
create unique index clan_one_pending_request on private.clan_requests(empire_id) where status='pending';
create index clan_pending_inbox on private.clan_requests(clan_id,requested_at) where status='pending';
alter table private.clan_requests enable row level security;
revoke all on private.clan_requests from public,anon,authenticated;

create or replace function private.manage_clan(p_action text,p_clan_id uuid default null,p_name text default null)
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
   update private.clan_requests set status='cancelled',reviewed_at=now() where empire_id=v_player and status='pending';
   return v_clan;
 elsif p_action='join' then
   if v_current.clan_id=p_clan_id then return p_clan_id; end if;
   if v_current.clan_id is not null then raise exception 'Quittez votre clan actuel avant d’en rejoindre un autre.'; end if;
   select id into v_clan from public.clans where id=p_clan_id and season_id=v_season;
   if v_clan is null then raise exception 'Ce clan n’est plus disponible dans cette session.'; end if;
   if exists(select 1 from private.clan_requests where empire_id=v_player and status='pending' and clan_id<>v_clan) then raise exception 'Annulez votre candidature en cours avant de choisir un autre clan.';end if;
   insert into private.clan_requests(empire_id,clan_id,season_id) values(v_player,v_clan,v_season) on conflict(empire_id) where status='pending' do nothing;
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

create function private.review_clan_request(p_request_id uuid,p_accept boolean) returns jsonb language plpgsql security definer set search_path='' as $$
declare e uuid;s uuid;c uuid;r private.clan_requests%rowtype;desired text;
begin
 select id into s from public.seasons where status='alpha' for update;e:=private.active_player_id();
 if p_accept is null then raise exception 'Décision invalide.';end if;
 select clan_id into c from private.clan_memberships where empire_id=e and role='founder';
 select * into r from private.clan_requests where id=p_request_id and clan_id=c and season_id=s for update;
 if not found then raise exception 'Candidature inaccessible : seul le chef du clan peut décider.' using errcode='42501';end if;
 desired:=case when p_accept then 'accepted' else 'declined' end;
 if r.status=desired then return jsonb_build_object('ok',true,'status',r.status);end if;
 if r.status<>'pending' then raise exception 'Cette candidature a déjà été traitée ou annulée.';end if;
 if p_accept then
  if exists(select 1 from private.clan_memberships where empire_id=r.empire_id) then raise exception 'Ce joueur appartient déjà à un clan.';end if;
  insert into private.clan_memberships(empire_id,clan_id,season_id,role) values(r.empire_id,r.clan_id,s,'member');
 end if;
 update private.clan_requests set status=desired,reviewed_at=now() where id=r.id;
 return jsonb_build_object('ok',true,'status',desired);
end $$;
create function public.review_clan_request(p_request_id uuid,p_accept boolean) returns jsonb language sql security invoker set search_path='' as $$select private.review_clan_request(p_request_id,p_accept);$$;

create function private.cancel_clan_request(p_request_id uuid) returns jsonb language plpgsql security definer set search_path='' as $$
declare e uuid;s uuid;r private.clan_requests%rowtype;
begin
 select id into s from public.seasons where status='alpha' for update;e:=private.active_player_id();
 select * into r from private.clan_requests where id=p_request_id and empire_id=e and season_id=s for update;
 if not found then raise exception 'Candidature inaccessible.' using errcode='42501';end if;
 if r.status not in ('pending','cancelled') then raise exception 'Cette candidature a déjà été traitée.';end if;
 update private.clan_requests set status='cancelled',reviewed_at=now() where id=r.id and status='pending';
 return jsonb_build_object('ok',true,'status','cancelled');
end $$;
create function public.cancel_clan_request(p_request_id uuid) returns jsonb language sql security invoker set search_path='' as $$select private.cancel_clan_request(p_request_id);$$;

create function private.clan_dashboard() returns jsonb language plpgsql security definer set search_path='' as $$
declare e uuid;c uuid;chief boolean;clan jsonb;members jsonb;incoming jsonb;outgoing jsonb;
begin
 e:=private.active_player_id();clan:=private.my_clan();c:=(clan->>'id')::uuid;chief:=clan->>'role'='founder';
 select coalesce(jsonb_agg(jsonb_build_object('username',p.username,'grade',e2.grade,'role',m.role,
 'planets',coalesce((select jsonb_agg(jsonb_build_object('id',w.id,'name',w.name,'tagged',w.clan_tag_visible,'appearance',w.race||'_'||w.resource) order by w.serial) from public.planets w where w.owner_empire_id=m.empire_id),'[]'::jsonb)) order by m.role='founder' desc,lower(p.username)),'[]'::jsonb)
 into members from private.clan_memberships m join public.empires e2 on e2.id=m.empire_id join public.profiles p on p.id=e2.player_id where m.clan_id=c;
 select coalesce(jsonb_agg(jsonb_build_object('id',r.id,'username',p.username,'grade',e2.grade,'requested_at',r.requested_at) order by r.requested_at),'[]'::jsonb)
 into incoming from private.clan_requests r join public.empires e2 on e2.id=r.empire_id join public.profiles p on p.id=e2.player_id where r.clan_id=c and chief and r.status='pending';
 select coalesce(jsonb_agg(jsonb_build_object('id',r.id,'clan_name',c2.name,'requested_at',r.requested_at) order by r.requested_at),'[]'::jsonb)
 into outgoing from private.clan_requests r join public.clans c2 on c2.id=r.clan_id where r.empire_id=e and r.status='pending';
 return jsonb_build_object('clan',clan,'members',members,'incoming',incoming,'outgoing',outgoing);
end $$;
create function public.clan_dashboard() returns jsonb language sql security invoker set search_path='' as $$select private.clan_dashboard();$$;

revoke all on function private.review_clan_request(uuid,boolean),public.review_clan_request(uuid,boolean),private.cancel_clan_request(uuid),public.cancel_clan_request(uuid),private.clan_dashboard(),public.clan_dashboard() from public,anon,authenticated;
grant execute on function private.review_clan_request(uuid,boolean),public.review_clan_request(uuid,boolean),private.cancel_clan_request(uuid),public.cancel_clan_request(uuid),private.clan_dashboard(),public.clan_dashboard() to authenticated;
