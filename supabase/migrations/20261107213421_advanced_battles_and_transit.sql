-- Settle the previous rules before activating the new military model.
select private.economy_process();
alter table private.fleets add column unavailable_until timestamptz not null default '-infinity',add column ground_ready_at timestamptz not null default '-infinity',add column route_x double precision,add column route_y double precision,add column camouflaged boolean not null default false;
update private.fleets set unavailable_until=coalesce(lands_at,'-infinity');
update private.fleets f set route_x=p.x,route_y=p.y from public.planets p where p.id=f.origin_id;
alter table public.planets add column captured_at timestamptz not null default now(),add column garrison_ready_at timestamptz not null default '-infinity',add column paranoid boolean not null default false,add column blockaded boolean not null default false,add column trade_resumes_at timestamptz not null default '-infinity',add column anonymous_until timestamptz;
update public.planets set captured_at=created_at;
alter table private.ship_jobs add column paused_at timestamptz;
create function private.travel_seconds(d double precision) returns integer language sql immutable set search_path='' as $$select ceil(3600+least(sqrt(2000000),greatest(0,d))/sqrt(2000000)*601200)::int$$;
create function private.fleet_position(f private.fleets,t timestamptz) returns table(x double precision,y double precision) language sql stable set search_path='' as $$
 select coalesce(f.route_x,o.x)+(p.x-coalesce(f.route_x,o.x))*q.k,coalesce(f.route_y,o.y)+(p.y-coalesce(f.route_y,o.y))*q.k from public.planets o join public.planets p on p.id=f.destination_id cross join lateral(select greatest(0,least(1,extract(epoch from(t-f.departed_at))/greatest(1,extract(epoch from(f.arrives_at-f.departed_at)))))::double precision k)q where o.id=f.origin_id;
$$;
create function private.same_clan(a uuid,b uuid) returns boolean language sql stable set search_path='' as $$select a=b or exists(select 1 from private.clan_memberships x join private.clan_memberships y on y.clan_id=x.clan_id where x.empire_id=a and y.empire_id=b)$$;
create function private.fortification(p public.planets,t timestamptz) returns numeric language sql immutable set search_path='' as $$
 with age as(select greatest(0,extract(epoch from(t-p.captured_at))/86400) d) select case when d<=7 then 0 when d<=60 then .6*power((d-7)/53,1.6) when d<150 then .6+.35*(1-power((150-d)/90,2)) else .95 end from age;
$$;
create function private.ground_superiority(pid uuid,t timestamptz) returns boolean language sql stable set search_path='' as $$
 select coalesce(sum(f.ground_soldiers) filter(where f.mission='attack' and f.ground_ready_at<=t),0)>coalesce(sum(f.ground_soldiers) filter(where f.mission='defend' and f.ground_ready_at<=t),0)+(case when p.garrison_ready_at<=t then p.soldiers else 0 end) from public.planets p left join private.fleets f on f.planet_id=p.id and f.status='stationed' where p.id=pid group by p.id;
$$;
create function private.sync_planet_war(pid uuid,t timestamptz) returns void language plpgsql set search_path='' as $$
declare ap numeric;dp numeric;n bigint;blocked boolean;p public.planets%rowtype;j record;
begin
 select * into p from public.planets where id=pid for update;
 select coalesce(sum((scouts+fighters*8)*(case when race='vael' then 1.15 when race='khar' then .85 else 1 end)) filter(where mission='attack'),0),coalesce(sum((scouts+fighters*8)*(case when race='vael' then 1.15 when race='khar' then .85 else 1 end)) filter(where mission='defend'),0),coalesce(sum(scouts::bigint+bombers+fighters) filter(where mission='attack'),0) into ap,dp,n from private.fleets where planet_id=pid and status='stationed';
 dp:=dp+(p.scouts+p.fighters*8)*(case when p.race='vael' then 1.15 when p.race='khar' then .85 else 1 end);
 blocked:=n>=100 and ap>=3*dp;
 update public.planets set blockaded=blocked,trade_resumes_at=case when blocked then 'infinity'::timestamptz when p.blockaded then t+interval '2 hours' else trade_resumes_at end where id=pid;
 if private.ground_superiority(pid,t) then update private.ship_jobs set paused_at=t where planet_id=pid and completed_at is null and cancelled_at is null and paused_at is null;
 else
  update private.ship_jobs set started_at=started_at+greatest(interval '0',t-paused_at),finishes_at=finishes_at+greatest(interval '0',t-paused_at),paused_at=null where planet_id=pid and completed_at is null and cancelled_at is null and paused_at is not null;
 end if;
end $$;
create function private.capture_military_state() returns trigger language plpgsql set search_path='' as $$
declare t timestamptz:=coalesce(nullif(current_setting('lw.development_at',true),'')::timestamptz,now());j record;hidden boolean;
begin
 if new.owner_empire_id is distinct from old.owner_empire_id then
  new.captured_at:=t;new.garrison_ready_at:=greatest(new.garrison_ready_at,t)+interval '1 hour';new.name:='Signal '||new.serial;new.rename_available:=true;new.clan_tag_visible:=false;
  if old.owner_empire_id is not null and old.scouts::bigint+old.bombers+old.fighters+old.soldiers>0 then
   insert into private.fleets(empire_id,season_id,name,race,supply_planet,planet_id,origin_id,mission,scouts,bombers,fighters,ground_soldiers,ground_ready_at) values(old.owner_empire_id,old.season_id,'Forces après conquête',old.race,old.id,old.id,old.id,'defend',old.scouts,old.bombers,old.fighters,old.soldiers,old.garrison_ready_at);
  end if;new.scouts:=0;new.bombers:=0;new.fighters:=0;new.soldiers:=0;
  if new.governance='tyrannie' then new.governance:='conseil';new.governance_changed_at:=t;end if;
  select coalesce(bool_or(camouflaged),false) into hidden from private.fleets where planet_id=new.id and empire_id=new.owner_empire_id and mission='attack' and ground_soldiers>0 and ground_ready_at<=t and status='stationed';
  new.anonymous_until:=case when hidden then t+interval '21 days' end;
  for j in update private.ship_jobs set cancelled_at=t where planet_id=new.id and completed_at is null and cancelled_at is null returning empire_id,cost loop update public.empires set treasury=treasury+j.cost where id=j.empire_id;end loop;
  update private.civilization_jobs set cancelled_at=t where planet_id=new.id and completed_at is null and cancelled_at is null;
  update private.fleets set mission=case mission when 'attack' then 'defend' else 'attack' end where destination_id=new.id and status='transit';
  update private.fleets set unavailable_until=greatest(unavailable_until,t)+interval '1 hour',ground_ready_at=greatest(ground_ready_at,t)+interval '1 hour' where planet_id=new.id and status='stationed';
  if not hidden then insert into private.battle_reports(empire_id,planet_id,occurred_at,event,details) select distinct f.empire_id,new.id,t,'takeover',jsonb_build_object('new_owner',p.username) from private.fleets f join public.empires e on e.id=new.owner_empire_id join public.profiles p on p.id=e.player_id where f.planet_id=new.id and f.status='stationed' and f.scouts::bigint+f.bombers+f.fighters+f.soldiers+f.ground_soldiers>0;end if;
 end if;return new;
end $$;
create trigger a_capture_military_state before update of owner_empire_id on public.planets for each row execute function private.capture_military_state();
create or replace function private.guard_governance() returns trigger language plpgsql set search_path='' as $$begin
 if new.governance is distinct from old.governance then
 if new.owner_empire_id is not distinct from old.owner_empire_id and old.governance_changed_at>now()-interval '72 hours' then raise exception 'Changement politique disponible le %.',old.governance_changed_at+interval '72 hours';end if;
 new.governance_changed_at:=coalesce(nullif(current_setting('lw.development_at',true),'')::timestamptz,now());end if;return new;end $$;
create or replace function private.teleport_capture_network() returns trigger language plpgsql set search_path='' as $$begin if new.owner_empire_id is distinct from old.owner_empire_id then new.teleport_ready_at:=coalesce(nullif(current_setting('lw.development_at',true),'')::timestamptz,now())+make_interval(hours=>4*(select count(*)::int from public.planets where owner_empire_id=new.owner_empire_id));end if;return new;end $$;


create or replace function private.galaxy_signals()
returns table(id uuid,designation text,x double precision,y double precision,clan_name text,is_own boolean)
language plpgsql security definer set search_path='' as $$
declare v_player uuid:=private.active_player_id(); v_season uuid;
begin
 select e.season_id into v_season from public.empires e where e.id=v_player;
 return query select p.id,
   case when p.name ~ '^Terra_Nullius_' then 'Signal '||p.serial else p.name end,
   p.x,p.y,case when p.clan_tag_visible then c.name else null end,
   coalesce(p.owner_empire_id=v_player,false)
 from public.planets p
 left join private.clan_memberships m on m.empire_id=p.owner_empire_id
 left join public.clans c on c.id=m.clan_id and c.season_id=p.season_id
 where p.season_id=v_season order by p.serial;
end $$;

create or replace function private.military_label(p_id uuid,p_empire uuid) returns text language sql stable set search_path='' as $$select case when name ~ '^Terra_Nullius_' then 'Signal '||serial else name end from public.planets where id=p_id$$;

create or replace function private.advance_planet_development(p_season uuid,p_at timestamptz) returns void language plpgsql set search_path='' as $$
declare p public.planets%rowtype;seconds numeric;growth numeric;energy_amount numeric;g jsonb;has_energy boolean;new_energy int;begin
 delete from private.teleport_attempts where attempted_at<least(p_at,now())-interval '1 day';
 for p in select * from public.planets where season_id=p_season and owner_empire_id is not null and development_last_at<p_at order by id for update loop
 seconds:=greatest(0,extract(epoch from(p_at-p.development_last_at)));g:=private.population_growth_state(p.id);
 growth:=p.population_fraction+p.population*(g->>'daily_rate')::numeric*seconds/86400;
 select exists(select 1 from private.player_technologies where empire_id=p.owner_empire_id and energy_unlocked_at is not null) into has_energy;
 if has_energy and p.energy<p.energy_max then
  energy_amount:=p.energy_fraction+seconds/3600;new_energy:=least(p.energy_max,p.energy+floor(energy_amount)::int);
  update public.planets set energy=new_energy,energy_fraction=case when new_energy=energy_max then 0 else energy_amount-floor(energy_amount) end where id=p.id;
 else update public.planets set energy_fraction=0 where id=p.id;end if;
 update public.planets set population=population+floor(growth)::bigint,population_fraction=growth-floor(growth),development_last_at=p_at where id=p.id;
 end loop;
end $$;

create or replace function private.technology_command(p_action text,p_args jsonb,p_request_id uuid) returns jsonb language plpgsql security definer set search_path='' as $$
declare v_e uuid;v_s uuid;v_prev private.technology_commands%rowtype;v_payload jsonb;v_result jsonb;v_tech text;v_cost bigint;v_q int;v_p public.planets%rowtype;v_t public.planets%rowtype;v_origin uuid;v_target uuid;v_energy_planet uuid;v_foreign uuid;v_code text:=coalesce(p_args->>'password','');v_hash text;v_secret text;v_clan uuid;v_other_clan uuid;v_allowed boolean;v_remaining int;v_take int;v_group record;v_available bigint;v_has boolean;v_at timestamptz:=now();
begin
 select id into v_s from public.seasons where status='alpha' for update;v_e:=private.active_player_id();
 if p_request_id is null or p_args is null or jsonb_typeof(p_args)<>'object' then raise exception 'Commande invalide.';end if;
 if octet_length(v_code)>72 then raise exception 'Code limité à 72 octets.';end if;
 v_payload:=jsonb_build_object('action',p_action,'args',p_args-'password');
 select * into v_prev from private.technology_commands where empire_id=v_e and request_id=p_request_id;
 if found then
  if v_prev.payload<>v_payload or (v_prev.secret_hash is not null and extensions.crypt(v_code,v_prev.secret_hash)<>v_prev.secret_hash) or (v_prev.secret_hash is null and v_code<>'') then raise exception 'Identifiant déjà utilisé pour une autre commande.';end if;
  return v_prev.result;
 end if;
 perform private.economy_process();
 insert into private.player_technologies(empire_id) values(v_e) on conflict do nothing;
 if p_action='research' then
  v_tech:=p_args->>'technology';if v_tech not in('energy','teleport') or v_tech is null then raise exception 'Technologie inconnue.';end if;
  select case when v_tech='energy' then energy_unlocked_at is not null else teleport_unlocked_at is not null end into v_has from private.player_technologies where empire_id=v_e;
  v_cost:=case when v_has then 0 when v_tech='energy' then 150000 else 300000 end;
  if exists(select 1 from public.empires where id=v_e and (treasury<v_cost or maintenance_debt>0)) then raise exception 'Trésorerie insuffisante ou entretien à régulariser.';end if;
  if not v_has then
   update public.empires set treasury=treasury-v_cost where id=v_e;
   if v_tech='energy' then
    update private.player_technologies set energy_unlocked_at=v_at where empire_id=v_e;
    update public.planets set energy=greatest(energy,10),energy_fraction=0,development_last_at=v_at where owner_empire_id=v_e;
   else update private.player_technologies set teleport_unlocked_at=v_at where empire_id=v_e;end if;
  end if;
  v_result:=jsonb_build_object('ok',true,'technology',v_tech,'cost',v_cost);
 elsif p_action in('energy_capacity','password') then
  select * into v_p from public.planets where id=(p_args->>'planet_id')::uuid and owner_empire_id=v_e and season_id=v_s for update;
  if not found then raise exception 'Planète inaccessible.' using errcode='42501';end if;
  if p_action='energy_capacity' then
   if not exists(select 1 from private.player_technologies where empire_id=v_e and energy_unlocked_at is not null) then raise exception 'Recherchez la recharge d’énergie.';end if;
   v_q:=(p_args->>'quantity')::int;
   if v_q is null or v_q<1 or v_q>100-v_p.energy_max then raise exception 'Extension énergétique invalide.';end if;
   if (p_args->>'expected_capacity')::int is distinct from v_p.energy_max then raise exception 'Le devis énergétique a changé. Actualisez.';end if;
   select sum(private.energy_capacity_price(n)) into v_cost from generate_series(v_p.energy_max+1,v_p.energy_max+v_q)n;
   if exists(select 1 from public.empires where id=v_e and (treasury<v_cost or maintenance_debt>0)) then raise exception 'Trésorerie insuffisante ou entretien à régulariser.';end if;
   update public.empires set treasury=treasury-v_cost where id=v_e;
   update public.planets set energy_max=energy_max+v_q where id=v_p.id;
   v_result:=jsonb_build_object('ok',true,'cost',v_cost,'capacity',v_p.energy_max+v_q);
  else
   if not exists(select 1 from private.player_technologies where empire_id=v_e and teleport_unlocked_at is not null) then raise exception 'Recherchez la téléportation.';end if;
   if v_code='' then delete from private.planet_teleport_access where planet_id=v_p.id;
   else
    if char_length(v_code)<8 then raise exception 'Le code doit contenir au moins 8 caractères.';end if;
    v_secret:=extensions.crypt(v_code,extensions.gen_salt('bf',10));
    insert into private.planet_teleport_access(planet_id,password_hash) values(v_p.id,v_secret) on conflict(planet_id) do update set password_hash=excluded.password_hash,changed_at=v_at;
   end if;
   v_result:=jsonb_build_object('ok',true,'configured',v_code<>'');
  end if;
 elsif p_action='teleport' then
  v_origin:=(p_args->>'origin_id')::uuid;v_target:=(p_args->>'target_id')::uuid;v_q:=(p_args->>'quantity')::int;
  select * into v_p from public.planets where id=v_origin and season_id=v_s for update;
  select * into v_t from public.planets where id=v_target and season_id=v_s for update;
  if v_p.id is null or v_t.id is null or v_origin=v_target or v_p.owner_empire_id is null or v_t.owner_empire_id is null or (v_p.owner_empire_id<>v_e and v_t.owner_empire_id<>v_e) then raise exception 'Destination ou origine indisponible.';end if;
  if v_q is null or v_q<1 then raise exception 'Nombre de soldats invalide.';end if;
  if not exists(select 1 from private.player_technologies where empire_id=v_p.owner_empire_id and teleport_unlocked_at is not null) or not exists(select 1 from private.player_technologies where empire_id=v_t.owner_empire_id and teleport_unlocked_at is not null) then raise exception 'Les deux propriétaires doivent avoir débloqué la téléportation.';end if;
  if v_p.teleport_ready_at>v_at or v_t.teleport_ready_at>v_at then raise exception 'Connexion au réseau de téléportation en cours.';end if;
  v_energy_planet:=case when v_p.owner_empire_id=v_e then v_p.id else v_t.id end;
  if not exists(select 1 from private.player_technologies where empire_id=v_e and energy_unlocked_at is not null) then raise exception 'Recherchez la recharge d’énergie.';end if;
  v_cost:=case when v_p.owner_empire_id=v_e and v_t.owner_empire_id=v_e then (v_q::bigint+9)/10 else (v_q::bigint+4)/5 end;
  if (select energy from public.planets where id=v_energy_planet)<v_cost then raise exception 'Énergie disponible insuffisante.';end if;
  select coalesce(sum(ground_soldiers),0)+(case when v_p.owner_empire_id=v_e and v_p.garrison_ready_at<=v_at then v_p.soldiers else 0 end) into v_available from private.fleets where empire_id=v_e and planet_id=v_origin and status='stationed' and ground_ready_at<=v_at;
  if v_q>v_available then raise exception 'Soldats au sol disponibles insuffisants.';end if;
  v_foreign:=case when v_p.owner_empire_id<>v_e then v_p.id when v_t.owner_empire_id<>v_e then v_t.id else null end;
  if v_foreign is not null then
   select clan_id into v_clan from private.clan_memberships where empire_id=v_e;
   select clan_id into v_other_clan from private.clan_memberships where empire_id=case when v_p.owner_empire_id<>v_e then v_p.owner_empire_id else v_t.owner_empire_id end;
   v_allowed:=v_clan is not null and v_other_clan is not null and v_clan=v_other_clan;
   if not v_allowed then
    if (select count(*) from private.teleport_attempts where empire_id=v_e and attempted_at>clock_timestamp()-interval '1 minute')>=10 or (select count(*) from private.teleport_attempts where planet_id=v_foreign and attempted_at>clock_timestamp()-interval '1 minute')>=20 then return jsonb_build_object('ok',false,'error','Trop de tentatives. Réessayez dans une minute.');end if;
    insert into private.teleport_attempts(empire_id,planet_id) values(v_e,v_foreign);
    select password_hash into v_hash from private.planet_teleport_access where planet_id=v_foreign;
    if v_hash is null or v_code='' or extensions.crypt(v_code,v_hash)<>v_hash then return jsonb_build_object('ok',false,'error','Accès de téléportation refusé.');end if;
   end if;
  end if;
  update public.planets set energy=energy-v_cost where id=v_energy_planet;
  v_remaining:=v_q;
  if v_p.owner_empire_id=v_e and v_p.garrison_ready_at<=v_at then
   v_take:=least(v_p.soldiers,v_remaining);
   if v_take>0 then
    update public.planets set soldiers=soldiers-v_take where id=v_p.id;
    insert into private.fleets(empire_id,season_id,name,race,supply_planet,planet_id,origin_id,mission,ground_soldiers,ground_ready_at) values(v_e,v_s,'Renforts téléportés',v_p.race,v_energy_planet,v_t.id,v_p.id,'defend',v_take,v_at+interval '1 hour');
    v_remaining:=v_remaining-v_take;
   end if;
  end if;
  for v_group in select * from private.fleets where empire_id=v_e and planet_id=v_p.id and status='stationed' and ground_ready_at<=v_at and ground_soldiers>0 order by id for update loop
   exit when v_remaining=0;v_take:=least(v_group.ground_soldiers,v_remaining);
   update private.fleets set ground_soldiers=ground_soldiers-v_take where id=v_group.id;
   insert into private.fleets(empire_id,season_id,name,race,supply_planet,planet_id,origin_id,mission,ground_soldiers,ground_ready_at) values(v_e,v_s,'Renforts téléportés',v_group.race,v_energy_planet,v_t.id,v_p.id,'defend',v_take,v_at+interval '1 hour');
   v_remaining:=v_remaining-v_take;
  end loop;
  if v_remaining<>0 then raise exception 'Soldats disponibles modifiés. Actualisez.';end if;
  update private.fleets set status='disbanded' where empire_id=v_e and planet_id=v_p.id and status='stationed' and ground_ready_at<=v_at and scouts::bigint+bombers+fighters+soldiers+ground_soldiers=0;
  insert into private.battle_reports(empire_id,planet_id,occurred_at,event,details) values(v_e,v_t.id,v_at,'arrival',jsonb_build_object('fleet','Renforts téléportés','mission','defend','lands_at',v_at,'teleport',true,'soldiers',v_q));
  v_result:=jsonb_build_object('ok',true,'quantity',v_q,'energy_cost',v_cost);
 else raise exception 'Action technologique inconnue.';end if;
 if v_code<>'' and v_secret is null then v_secret:=extensions.crypt(v_code,extensions.gen_salt('bf',10));end if;
 insert into private.technology_commands(empire_id,request_id,payload,result,secret_hash) values(v_e,p_request_id,v_payload,v_result,v_secret);
 delete from private.teleport_attempts where attempted_at<clock_timestamp()-interval '1 day';
 return v_result;
end $$;

create or replace function private.technology_dashboard() returns jsonb language plpgsql security definer set search_path='' as $$
declare v_e uuid;v_s uuid;v_clan uuid;v_energy boolean;v_teleport boolean;v_result jsonb;begin
 select id into v_s from public.seasons where status='alpha' for update;v_e:=private.active_player_id();perform private.economy_process();
 select exists(select 1 from private.player_technologies where empire_id=v_e and energy_unlocked_at is not null),exists(select 1 from private.player_technologies where empire_id=v_e and teleport_unlocked_at is not null) into v_energy,v_teleport;
 select clan_id into v_clan from private.clan_memberships where empire_id=v_e;
 select jsonb_build_object('server_now',now(),'energy_unlocked',v_energy,'teleport_unlocked',v_teleport,'energy_cost',150000,'teleport_cost',300000,
 'energy_prices',(select jsonb_object_agg(n::text,private.energy_capacity_price(n)) from generate_series(11,100)n),
 'planets',coalesce((select jsonb_agg(to_jsonb(p)||jsonb_build_object('growth',private.population_growth_state(p.id),'code_configured',exists(select 1 from private.planet_teleport_access where planet_id=p.id),
 'next_recharge_at',case when v_energy and p.energy<p.energy_max then p.development_last_at+make_interval(secs=>((1-p.energy_fraction)*3600)::double precision) end) order by p.serial) from public.planets p where owner_empire_id=v_e),'[]'),
 'origins',coalesce((select jsonb_agg(jsonb_build_object('id',p.id,'name',p.name,'x',p.x,'y',p.y,'is_own',p.owner_empire_id=v_e,'energy',case when p.owner_empire_id=v_e then p.energy else null end,
 'available_soldiers',(case when p.owner_empire_id=v_e and p.garrison_ready_at<=now() then p.soldiers else 0 end)+coalesce((select sum(ground_soldiers) from private.fleets where empire_id=v_e and planet_id=p.id and status='stationed' and ground_ready_at<=now()),0),
 'network_ready_at',p.teleport_ready_at,'access',case when p.owner_empire_id=v_e then 'own' when v_clan is not null and exists(select 1 from private.clan_memberships where empire_id=p.owner_empire_id and clan_id=v_clan) then 'clan' else 'password' end) order by p.serial)
 from public.planets p where p.season_id=v_s and (p.owner_empire_id=v_e or exists(select 1 from private.fleets where empire_id=v_e and planet_id=p.id and status='stationed' and ground_ready_at<=now() and ground_soldiers>0)) and p.owner_empire_id is not null and (p.owner_empire_id=v_e or exists(select 1 from private.player_technologies where empire_id=p.owner_empire_id and teleport_unlocked_at is not null))),'[]'),
 'targets',coalesce((select jsonb_agg(jsonb_build_object('id',p.id,'name',p.name,'x',p.x,'y',p.y,'is_own',p.owner_empire_id=v_e,'energy',case when p.owner_empire_id=v_e then p.energy else null end,'network_ready_at',p.teleport_ready_at,
 'access',case when p.owner_empire_id=v_e then 'own' when v_clan is not null and exists(select 1 from private.clan_memberships where empire_id=p.owner_empire_id and clan_id=v_clan) then 'clan' else 'password' end) order by p.serial)
 from public.planets p where p.season_id=v_s and v_teleport and exists(select 1 from private.player_technologies where empire_id=p.owner_empire_id and teleport_unlocked_at is not null)
 and (p.owner_empire_id=v_e or (v_clan is not null and exists(select 1 from private.clan_memberships where empire_id=p.owner_empire_id and clan_id=v_clan)) or exists(select 1 from private.planet_teleport_access where planet_id=p.id))),'[]')) into v_result;
 return v_result;end $$;

create or replace function private.resolve_battle(p_planet uuid,p_at timestamptz) returns void language plpgsql set search_path='' as $$
#variable_conflict use_column
declare p public.planets%rowtype;snap jsonb;u record;t record;d private.battle_damage%rowtype;att record;def record;
 enemy record;sr numeric;gr numeric;ls integer;lb integer;lf integer;lg integer;ns integer;nb integer;nf integer;ng integer;nc integer;
 winner uuid;old_owner uuid;visible_ground boolean;my_before jsonb;my_after jsonb;enemy_space jsonb;enemy_ground jsonb;event_name text;fort numeric;
begin
 perform set_config('lw.development_at',p_at::text,true);
 select * into p from public.planets where id=p_planet for update;
 fort:=1+private.fortification(p,p_at);
 perform private.sync_planet_war(p.id,p_at);
 select jsonb_agg(to_jsonb(q)) into snap from(
 select p.id id,p.owner_empire_id empire_id,'defend'::text side,p.race,p.scouts,p.bombers,p.fighters,p.soldiers ground,0 cargo,true local,case when p.garrison_ready_at<=p_at then p.soldiers else 0 end ready
 union all select f.id,f.empire_id,f.mission,f.race,f.scouts,f.bombers,f.fighters,f.ground_soldiers,f.soldiers,false,case when f.ground_ready_at<=p_at then f.ground_soldiers else 0 end from private.fleets f where f.planet_id=p.id and f.status='stationed'
 ) q;
 select sum(scouts*2+bombers*10+fighters*12)::numeric hp,sum((scouts+fighters*8)*(case when race='vael' then 1.15 when race='khar' then .85 else 1 end))::numeric power,sum(ready)::numeric ground,sum(ready*(case when race='khar' then 1.15 when race='vael' then .85 else 1 end))::numeric ground_power,sum(bombers)::numeric bombers into att from jsonb_to_recordset(snap) as x(side text,race text,scouts int,bombers int,fighters int,ground int,ready int) where side='attack';
 select sum(scouts*2+bombers*10+fighters*12)::numeric hp,sum((scouts+fighters*8)*(case when race='vael' then 1.15 when race='khar' then .85 else 1 end))::numeric power,sum(ready)::numeric ground,sum(ready*(case when race='khar' then 1.15 when race='vael' then .85 else 1 end))::numeric ground_power,sum(bombers)::numeric bombers into def from jsonb_to_recordset(snap) as x(side text,race text,scouts int,bombers int,fighters int,ground int,ready int) where side='defend';
 if coalesce(att.hp,0)+coalesce((select sum(ground) from jsonb_to_recordset(snap) as z(side text,ground int) where side='attack'),0)=0 then return;end if;
 def.ground_power:=coalesce(def.ground_power,0)*fort;
 if coalesce(def.hp,0)+coalesce((select sum(ground) from jsonb_to_recordset(snap) as z(side text,ground int) where side='defend'),0)>0 then
 for u in select * from jsonb_to_recordset(snap) as x(id uuid,empire_id uuid,side text,race text,scouts int,bombers int,fighters int,ground int,cargo int,local boolean) loop
   if u.side='attack' then
     sr:=least(1,(coalesce(def.power,0)+coalesce(def.ground_power,0)*.1)*.12/greatest(coalesce(att.hp,0),1));
     gr:=least(1,(coalesce(def.ground_power,0)*.04+case when coalesce(def.power,0)>=3*coalesce(att.power,0) then coalesce(def.bombers,0)*2 else 0 end)/greatest((select sum(ground) from jsonb_to_recordset(snap) as z(side text,ground int) where side='attack'),1));
   else
     sr:=least(1,coalesce(att.power,0)*.12/greatest(coalesce(def.hp,0),1));
     gr:=least(1,((coalesce(att.ground_power,0)*.04+case when coalesce(att.power,0)>=3*coalesce(def.power,0) then coalesce(att.bombers,0)*2 else 0 end)/fort)/greatest((select sum(ground) from jsonb_to_recordset(snap) as z(side text,ground int) where side='defend'),1));
   end if;
   insert into private.battle_damage(planet_id,force_id) values(p.id,u.id) on conflict do nothing;
   select * into d from private.battle_damage where planet_id=p.id and force_id=u.id;
   ls:=least(u.scouts,floor(u.scouts*sr+d.scouts)::int);lb:=least(u.bombers,floor(u.bombers*sr+d.bombers)::int);lf:=least(u.fighters,floor(u.fighters*sr+d.fighters)::int);lg:=least(u.ground,floor(u.ground*gr+d.ground)::int);
   ns:=u.scouts-ls;nb:=u.bombers-lb;nf:=u.fighters-lf;ng:=u.ground-lg;
   nc:=least(10*(nb+nf),floor(u.cargo*(case when u.bombers+u.fighters=0 then 0 else (nb+nf)::numeric/(u.bombers+u.fighters) end))::int);
   update private.battle_damage set scouts=u.scouts*sr+d.scouts-ls,bombers=u.bombers*sr+d.bombers-lb,fighters=u.fighters*sr+d.fighters-lf,ground=u.ground*gr+d.ground-lg where planet_id=p.id and force_id=u.id;
   perform private.credit_battle_losses(snap,u.empire_id,u.side,ls::numeric*4+lb::numeric*24+lf::numeric*32+(u.cargo-nc),lg);
   if u.local then update public.planets set scouts=ns,bombers=nb,fighters=nf,soldiers=ng where id=p.id;
   else update private.fleets set scouts=ns,bombers=nb,fighters=nf,soldiers=nc,ground_soldiers=ng,status=case when ns+nb+nf+ng+nc=0 then 'destroyed' else status end where id=u.id;end if;
 end loop;
 end if;
 select * into p from public.planets where id=p.id;
 if (p.garrison_ready_at>p_at or p.soldiers=0) and not exists(select 1 from private.fleets where planet_id=p.id and status='stationed' and mission='defend' and ground_ready_at<=p_at and ground_soldiers>0) then
   select empire_id into winner from private.fleets where planet_id=p.id and status='stationed' and mission='attack' and ground_ready_at<=p_at and ground_soldiers>0 group by empire_id order by sum(ground_soldiers) desc,empire_id limit 1;
   if winner is not null and winner is distinct from p.owner_empire_id and (select count(*) from public.planets where owner_empire_id=winner)<12 then
     old_owner:=p.owner_empire_id;
     update public.planets set owner_empire_id=winner,rename_available=true,clan_tag_visible=false,recruitment_fraction=0 where id=p.id;

     update private.fleets set mission='defend' where planet_id=p.id and status='stationed' and mission='attack';
     perform private.sync_planet_war(p.id,p_at);
     event_name:='capture';
   else event_name:='battle';end if;
 else event_name:='battle';end if;
 perform private.sync_planet_war(p.id,p_at);
 for t in select distinct empire_id,side from jsonb_to_recordset(snap) as x(empire_id uuid,side text) where empire_id is not null loop
   select coalesce(sum(ground),0)>0,jsonb_build_object('scouts',coalesce(sum(scouts),0),'bombers',coalesce(sum(bombers),0),'fighters',coalesce(sum(fighters),0),'soldiers',coalesce(sum(ground+cargo),0)) into visible_ground,my_before from jsonb_to_recordset(snap) as x(empire_id uuid,scouts int,bombers int,fighters int,ground int,cargo int) where empire_id=t.empire_id;
   select jsonb_build_object('scouts',coalesce(sum(scouts),0),'bombers',coalesce(sum(bombers),0),'fighters',coalesce(sum(fighters),0)) into enemy_space from jsonb_to_recordset(snap) as x(side text,scouts int,bombers int,fighters int) where side<>t.side;
   enemy_ground:=null;if visible_ground then select to_jsonb(coalesce(sum(ground),0)) into enemy_ground from jsonb_to_recordset(snap) as x(side text,ground int) where side<>t.side;end if;
   select jsonb_build_object('scouts',sum(scouts),'bombers',sum(bombers),'fighters',sum(fighters),'soldiers',sum(soldiers)) into my_after from (
    select scouts,bombers,fighters,soldiers from public.planets where id=p.id and owner_empire_id=t.empire_id
    union all select scouts,bombers,fighters,soldiers+ground_soldiers from private.fleets where planet_id=p.id and empire_id=t.empire_id and status='stationed'
    union all select 0,0,0,0) z;
   insert into private.battle_reports(empire_id,planet_id,occurred_at,event,details) values(t.empire_id,p.id,p_at,event_name,jsonb_build_object('mission',t.side,'before',my_before,'after',my_after,'enemy_space',enemy_space,'enemy_ground',enemy_ground,'captured',winner=t.empire_id and event_name='capture'));
 end loop;
end $$;

create or replace function private.credit_battle_losses(p_snapshot jsonb,p_victim uuid,p_side text,p_space_points numeric,p_ground_points numeric) returns void language plpgsql set search_path='' as $$
declare total_space numeric;total_ground numeric;v record;credit numeric;
begin
 select coalesce(sum((scouts+fighters*8)*(case when race='vael' then 1.15 when race='khar' then .85 else 1 end)),0),coalesce(sum(coalesce(ready,ground)*.04*(case when race='khar' then 1.15 when race='vael' then .85 else 1 end)+bombers*2),0)
 into total_space,total_ground from jsonb_to_recordset(p_snapshot) as x(side text,race text,scouts int,bombers int,fighters int,ground int,ready int) where side<>p_side;
 for v in select empire_id,sum((scouts+fighters*8)*(case when race='vael' then 1.15 when race='khar' then .85 else 1 end)) space_power,sum(coalesce(ready,ground)*.04*(case when race='khar' then 1.15 when race='vael' then .85 else 1 end)+bombers*2) ground_power
 from jsonb_to_recordset(p_snapshot) as x(empire_id uuid,side text,race text,scouts int,bombers int,fighters int,ground int,ready int)
 where side<>p_side and empire_id is not null and empire_id is distinct from p_victim
 and not exists(select 1 from private.clan_memberships a join private.clan_memberships b on a.clan_id=b.clan_id where a.empire_id=x.empire_id and b.empire_id=p_victim)
 group by empire_id loop
 credit:=coalesce(p_space_points*v.space_power/nullif(total_space,0),0)+coalesce(p_ground_points*v.ground_power/nullif(total_ground,0),0);
 if credit>0 then insert into private.player_merit(empire_id,destroyed_points) values(v.empire_id,credit) on conflict(empire_id) do update set destroyed_points=private.player_merit.destroyed_points+excluded.destroyed_points;end if;
 end loop;
end $$;

create or replace function private.military_command(p_action text,p_args jsonb,p_request_id uuid) returns jsonb language plpgsql security definer set search_path='' as $$
#variable_conflict use_column
declare e uuid;s uuid;p public.planets%rowtype;target public.planets%rowtype;f private.fleets%rowtype;prev private.military_commands%rowtype;g record;payload jsonb;r jsonb;pid uuid;fid uuid;kind text;q int;n int;ns int;nb int;nf int;delta int;remaining int;take_n int;cost bigint;hours numeric;distance numeric;v_id uuid;v_at timestamptz:=now();rx double precision;ry double precision;
begin
 select id into s from public.seasons where status='alpha' for update;e:=private.active_player_id();
 if p_request_id is null or p_args is null or jsonb_typeof(p_args)<>'object' then raise exception 'Commande invalide.';end if;
 payload:=jsonb_build_object('action',p_action,'args',p_args);select * into prev from private.military_commands where empire_id=e and request_id=p_request_id;
 if found then if prev.payload<>payload then raise exception 'Identifiant déjà utilisé pour une autre commande.';end if;return prev.result;end if;
 perform private.economy_process();
 pid:=(p_args->>'planet_id')::uuid;fid:=(p_args->>'fleet_id')::uuid;
 if p_action in ('recruitment','factory','ship','assemble','rename','paranoid') then
 select * into p from public.planets where id=pid and owner_empire_id=e and season_id=s for update;if not found then raise exception 'Planète inaccessible.' using errcode='42501';end if;
 end if;
 if p_action in ('load','dispatch','disband','mission','redirect') then
 select * into f from private.fleets where id=fid and empire_id=e and (status='stationed' or (p_action='redirect' and status='transit')) for update;if not found then raise exception 'Flotte indisponible.' using errcode='42501';end if;
 select * into p from public.planets where id=f.planet_id for update;
 end if;
 if p_action in ('load','dispatch','disband') and f.unavailable_until>v_at then raise exception 'Flotte N/A : attendez la fin de son indisponibilité.';end if;
 if p_action in ('factory','ship') and private.ground_superiority(p.id,v_at) then raise exception 'Production suspendue : contrôle planétaire contesté.';end if;
 if p_action='paranoid' then
 if jsonb_typeof(p_args->'enabled') is distinct from 'boolean' then raise exception 'Choix invalide.';end if;
 update public.planets set paranoid=(p_args->>'enabled')::boolean where id=p.id;
 elsif p_action='recruitment' then
 if jsonb_typeof(p_args->'enabled') is distinct from 'boolean' then raise exception 'Choix de recrutement invalide.';end if;
 update public.planets set recruitment_enabled=(p_args->>'enabled')::boolean where id=p.id;
 elsif p_action='rename' then
 if p_args->>'name' is null or not p.rename_available or char_length(btrim(p_args->>'name')) not between 3 and 40 then raise exception 'Renommage indisponible ou nom invalide.';end if;
 update public.planets set name=btrim(p_args->>'name'),rename_available=false where id=p.id;
 elsif p_action in ('factory','ship') then
 if p_action='factory' then
  if p_args->>'expected_factories' is null or (p_args->>'expected_factories')::int<>p.factories then raise exception 'Le devis des usines a changé. Actualisez avant de confirmer.';end if;
  if p.factories>=200 or exists(select 1 from private.ship_jobs where planet_id=p.id and kind='factory' and completed_at is null and cancelled_at is null) then raise exception 'Un chantier d’usine est déjà en cours, ou la limite est atteinte.';end if;
  kind:='factory';q:=1;cost:=private.factory_price(p.factories+1);hours:=24*(1+.08*(p.factories-5));
 else
  kind:=p_args->>'kind';q:=(p_args->>'quantity')::int;
  if kind is null or kind not in ('scout','bomber','fighter') or q is null or q not between 1 and 200 then raise exception 'Production invalide.';end if;
  if q>p.factories-(select count(*) from private.ship_jobs where planet_id=p.id and kind<>'factory' and completed_at is null and cancelled_at is null) then raise exception 'Pas assez d’usines libres.';end if;
  cost:=(case kind when 'scout' then 2000 when 'bomber' then 12000 else 16000 end)*q;hours:=case kind when 'scout' then 2 when 'bomber' then 8 else 10 end;
 end if;
 if exists(select 1 from public.empires where id=e and (treasury<cost or maintenance_debt>0)) then raise exception 'Trésorerie insuffisante ou entretien à régulariser.';end if;
 update public.empires set treasury=treasury-cost where id=e;
 for n in 1..q loop insert into private.ship_jobs(empire_id,planet_id,kind,cost,started_at,finishes_at) values(e,p.id,kind,cost/q,v_at,v_at+make_interval(secs=>(hours*3600/(case when p.resource='ferros' then 1.15 else 1 end))::double precision)) returning id into v_id;end loop;
 elsif p_action='assemble' then
 ns:=(p_args->>'scouts')::int;nb:=(p_args->>'bombers')::int;nf:=(p_args->>'fighters')::int;
 if ns is null or nb is null or nf is null or least(ns,nb,nf)<0 or ns::bigint+nb+nf<1 or ns>p.scouts or nb>p.bombers or nf>p.fighters or char_length(btrim(p_args->>'name')) not between 1 and 40 or p_args->>'name' is null then raise exception 'Composition de flotte invalide.';end if;
 q:=coalesce((p_args->>'soldiers')::int,0);
 if q<0 or q>p.soldiers then raise exception 'Soldats disponibles insuffisants ou quantité invalide.';end if;
 if q::bigint>10::bigint*(nb::bigint+nf) then raise exception 'Capacité de transport dépassée.';end if;
 if q>0 and p.garrison_ready_at>v_at then raise exception 'Armées N/A.';end if;
 update public.planets set scouts=scouts-ns,bombers=bombers-nb,fighters=fighters-nf,soldiers=soldiers-q where id=p.id;
 insert into private.fleets(empire_id,season_id,name,race,supply_planet,planet_id,origin_id,scouts,bombers,fighters,soldiers,created_at) values(e,s,btrim(p_args->>'name'),p.race,p.id,p.id,p.id,ns,nb,nf,q,v_at) returning id into v_id;
 elsif p_action='mission' then
 if p_args->>'mission' is null or p_args->>'mission' not in ('attack','defend') or (p_args->>'mission'='attack' and p.owner_empire_id=e) then raise exception 'Mission invalide.';end if;
 if f.mission<>p_args->>'mission' then update private.fleets set mission=p_args->>'mission',unavailable_until=case when p_args->>'mission'='defend' then least(v_at+interval '4 hours',greatest(unavailable_until,v_at)+interval '1 hour') else greatest(unavailable_until,v_at+interval '1 hour') end,ground_ready_at=case when p_args->>'mission'='defend' then least(v_at+interval '4 hours',greatest(ground_ready_at,v_at)+interval '1 hour') else greatest(ground_ready_at,v_at+interval '1 hour') end where id=f.id;end if;
 perform private.sync_planet_war(p.id,v_at);
 elsif p_action='redirect' then
 if f.status<>'transit' then raise exception 'Flotte hors transit.';end if;
 select * into target from public.planets where id=(p_args->>'target_id')::uuid and season_id=s;
 if not found then raise exception 'Destination invalide.';end if;
 select x,y into rx,ry from private.fleet_position(f,v_at);distance:=sqrt(power(target.x-rx,2)+power(target.y-ry,2));
 update private.fleets set route_x=rx,route_y=ry,destination_id=target.id,departed_at=v_at,arrives_at=v_at+make_interval(secs=>private.travel_seconds(distance)) where id=f.id;
 elsif p_action='load' then
 q:=(p_args->>'soldiers')::int;if q is null or q<0 or q>10*(f.bombers+f.fighters) then raise exception 'Capacité de transport dépassée.';end if;
 delta:=q-f.soldiers;
 if delta<0 and f.lands_at is not null and v_at<f.lands_at then raise exception 'Le débarquement doit attendre une heure après l’arrivée.';end if;
 if delta>0 then
  remaining:=delta;
  if p.owner_empire_id=e and p.garrison_ready_at<=v_at then take_n:=least(p.soldiers,remaining);update public.planets set soldiers=soldiers-take_n where id=p.id;remaining:=remaining-take_n;end if;
  for g in select * from private.fleets where empire_id=e and planet_id=p.id and status='stationed' and ground_soldiers>0 and ground_ready_at<=v_at order by id for update loop
   take_n:=least(g.ground_soldiers,remaining);update private.fleets set ground_soldiers=ground_soldiers-take_n where id=g.id;remaining:=remaining-take_n;exit when remaining=0;
  end loop;
  if remaining>0 then raise exception 'Soldats disponibles insuffisants.';end if;
 elsif delta<0 then
  if p.owner_empire_id=e then update public.planets set soldiers=soldiers-delta where id=p.id;
  else update private.fleets set ground_soldiers=ground_soldiers-delta where id=f.id;end if;
 end if;
 update private.fleets set soldiers=q where id=f.id;
 elsif p_action='dispatch' then
 select * into target from public.planets where id=(p_args->>'target_id')::uuid and season_id=s;
 if not found or target.id=p.id or f.scouts+f.bombers+f.fighters=0 or p_args->>'mission' is null or p_args->>'mission' not in ('attack','defend') or (target.owner_empire_id=e and p_args->>'mission'='attack') then raise exception 'Destination ou mission invalide.';end if;
 if f.ground_soldiers>0 then insert into private.fleets(empire_id,season_id,name,race,supply_planet,planet_id,origin_id,mission,ground_soldiers,created_at) values(e,s,left(f.name||' · garnison',40),f.race,f.supply_planet,p.id,p.id,f.mission,f.ground_soldiers,v_at);end if;
 distance:=sqrt(power(target.x-p.x,2)+power(target.y-p.y,2));
 update private.fleets set origin_id=p.id,destination_id=target.id,planet_id=null,status='transit',mission=p_args->>'mission',departed_at=v_at,route_x=p.x,route_y=p.y,arrives_at=v_at+make_interval(secs=>private.travel_seconds(distance)),lands_at=null,ground_soldiers=0 where id=f.id;
 perform private.sync_planet_war(p.id,v_at);
 elsif p_action='disband' then
 if f.ground_ready_at>v_at then raise exception 'Armées N/A.';end if;
 if p.owner_empire_id is distinct from e then raise exception 'Ralliez un monde sous votre contrôle pour dissoudre cette flotte.';end if;
 update public.planets set scouts=scouts+f.scouts,bombers=bombers+f.bombers,fighters=fighters+f.fighters,soldiers=soldiers+f.soldiers+f.ground_soldiers where id=p.id;
 update private.fleets set status='disbanded',scouts=0,bombers=0,fighters=0,soldiers=0,ground_soldiers=0 where id=f.id;
 else raise exception 'Action inconnue.';end if;
 if p.id is not null then perform private.sync_planet_war(p.id,v_at);end if;
 r:=jsonb_build_object('ok',true,'id',coalesce(v_id,fid,pid));insert into private.military_commands values(e,p_request_id,payload,r);return r;
end $$;

create or replace function private.military_process(p_now timestamptz default now()) returns void language plpgsql security definer set search_path='' as $$
#variable_conflict use_column
declare c private.military_clock%rowtype;s record;v_at timestamptz;v_limit timestamptz;j record;f record;b record;p public.planets%rowtype;amount numeric;n int;
begin
 for s in select id,ends_at from public.seasons where status='alpha' order by id loop
 perform 1 from public.seasons where id=s.id for update;
 select * into c from private.military_clock where season_id=s.id for update;if not found then continue;end if;
 v_limit:=least(p_now,s.ends_at);
 loop
   select least(coalesce((select min(ground_ready_at) from private.fleets where season_id=s.id and status='stationed' and ground_ready_at>c.last_processed and ground_ready_at<'infinity'),'infinity'),c.next_tick,coalesce((select min(cj.finishes_at) from private.civilization_jobs cj join public.planets cp on cp.id=cj.planet_id where cp.season_id=s.id and cj.completed_at is null and cj.cancelled_at is null),'infinity'),coalesce((select min(finishes_at) from private.ship_jobs j join public.planets p on p.id=j.planet_id where p.season_id=s.id and completed_at is null and cancelled_at is null and j.paused_at is null),'infinity'),coalesce((select min(arrives_at) from private.fleets where season_id=s.id and status='transit'),'infinity')) into v_at;
   exit when v_at>v_limit;
   perform private.economy_process_base(v_at);
   perform private.advance_planet_development(s.id,v_at);
   perform set_config('lw.development_at',v_at::text,true);
   for b in select id from public.planets p where season_id=s.id and (blockaded or exists(select 1 from private.fleets f where f.planet_id=p.id and status='stationed' and mission='attack') or exists(select 1 from private.ship_jobs j where j.planet_id=p.id and paused_at is not null and completed_at is null and cancelled_at is null)) loop perform private.sync_planet_war(b.id,v_at);end loop;
   for j in select cj.* from private.civilization_jobs cj join public.planets cp on cp.id=cj.planet_id where cp.season_id=s.id and cj.completed_at is null and cj.cancelled_at is null and cj.finishes_at<=v_at order by cj.finishes_at,cj.target_level loop
    update public.planets set civilization=j.target_level where id=j.planet_id and owner_empire_id=j.empire_id and civilization=j.target_level-1;
    if found then update private.civilization_jobs set completed_at=v_at where id=j.id;
    else update private.civilization_jobs set cancelled_at=v_at where id=j.id;end if;
   end loop;
   for j in select j.* from private.ship_jobs j join public.planets p on p.id=j.planet_id where p.season_id=s.id and completed_at is null and cancelled_at is null and j.paused_at is null and finishes_at<=v_at order by finishes_at,j.id loop
    update public.planets set factories=factories+case when j.kind='factory' then 1 else 0 end,scouts=scouts+case when j.kind='scout' then 1 else 0 end,bombers=bombers+case when j.kind='bomber' then 1 else 0 end,fighters=fighters+case when j.kind='fighter' then 1 else 0 end where id=j.planet_id and owner_empire_id=j.empire_id;
    update private.ship_jobs set completed_at=v_at,cancelled_at=case when not exists(select 1 from public.planets where id=j.planet_id and owner_empire_id=j.empire_id) then v_at end where id=j.id;
   end loop;
   for f in select * from private.fleets where season_id=s.id and status='transit' and arrives_at<=v_at order by arrives_at,id loop
    update private.fleets set status='stationed',planet_id=destination_id,lands_at=arrives_at+interval '1 hour',unavailable_until=arrives_at+interval '1 hour',ground_ready_at=arrives_at+interval '1 hour',mission=case when exists(select 1 from public.planets where id=f.destination_id and paranoid and not coalesce(private.same_clan(owner_empire_id,f.empire_id),false)) then 'attack' else mission end where id=f.id;
    perform private.sync_planet_war(f.destination_id,v_at);
    insert into private.battle_reports(empire_id,planet_id,occurred_at,event,details) values(f.empire_id,f.destination_id,v_at,'arrival',jsonb_build_object('fleet',f.name,'lands_at',f.arrives_at+interval '1 hour','mission',(select mission from private.fleets where id=f.id)));
   end loop;
   if v_at=c.next_tick then
    for p in select * from public.planets where season_id=s.id and owner_empire_id is not null and recruitment_enabled and not private.ground_superiority(id,v_at) and soldiers<greatest(1,population/1000) loop
      amount:=p.recruitment_fraction+private.recruitment_daily(p)/24;n:=least(greatest(1,p.population/1000)-p.soldiers,floor(amount)::bigint)::int;
      update public.planets set soldiers=soldiers+n,recruitment_fraction=amount-floor(amount) where id=p.id;
      if n>0 then insert into private.player_merit(empire_id,produced_soldiers) values(p.owner_empire_id,n) on conflict(empire_id) do update set produced_soldiers=private.player_merit.produced_soldiers+excluded.produced_soldiers;end if;
    end loop;
    update private.fleets set ground_soldiers=ground_soldiers+soldiers,soldiers=0,lands_at=null where season_id=s.id and status='stationed' and lands_at<=v_at and unavailable_until<=v_at;
    for b in select id from public.planets p where season_id=s.id and (blockaded or exists(select 1 from private.fleets f where f.planet_id=p.id and status='stationed' and mission='attack') or exists(select 1 from private.ship_jobs j where j.planet_id=p.id and paused_at is not null and completed_at is null and cancelled_at is null)) loop perform private.sync_planet_war(b.id,v_at);end loop;
    for b in select distinct planet_id id from private.fleets where season_id=s.id and status='stationed' and mission='attack' loop perform private.resolve_battle(b.id,v_at);end loop;
    c.next_tick:=c.next_tick+interval '1 hour';
   end if;
   c.last_processed:=v_at;
 end loop;
 perform private.economy_process_base(v_limit);
 perform private.advance_planet_development(s.id,v_limit);
 perform set_config('lw.development_at','',true);
 update private.military_clock set last_processed=v_limit,next_tick=c.next_tick where season_id=s.id;
 perform private.refresh_ranks(s.id);
 end loop;
end $$;

create or replace function private.military_dashboard() returns jsonb language plpgsql security definer set search_path='' as $$
#variable_conflict use_column
declare e uuid;s uuid;r jsonb;
begin
 select id into s from public.seasons where status='alpha' for update;e:=private.active_player_id();perform private.economy_process();
 select jsonb_build_object('server_now',now(),'next_tick',(select next_tick from private.military_clock where season_id=s),'treasury',(select treasury from public.empires where id=e),'debt',(select maintenance_debt from public.empires where id=e),
 'planets',coalesce((select jsonb_agg(to_jsonb(p)||jsonb_build_object('fortification',private.fortification(p,now()),'contested',private.ground_superiority(p.id,now()),'daily_recruits',case when private.ground_superiority(p.id,now()) then 0 else private.recruitment_daily(p) end,'available_soldiers',case when p.garrison_ready_at<=now() then p.soldiers else 0 end,'recruitment_cap',greatest(1,p.population/1000),'factory_price',private.factory_price(p.factories+1),'factory_hours',24*(1+.08*(p.factories-5))/(case when p.resource='ferros' then 1.15 else 1 end),'busy_factories',(select count(*) from private.ship_jobs where planet_id=p.id and kind<>'factory' and completed_at is null and cancelled_at is null))) from public.planets p where owner_empire_id=e),'[]'::jsonb),
 'fleets',coalesce((select jsonb_agg(to_jsonb(f)||jsonb_build_object('position',case when f.status='transit' then (select to_jsonb(q) from private.fleet_position(f,now()) q) end,'location',private.military_label(f.planet_id,e),'origin',case when f.status='transit' and exists(select 1 from public.planets o where o.id=f.origin_id and (o.x is distinct from f.route_x or o.y is distinct from f.route_y)) then 'Position en vol' else private.military_label(f.origin_id,e) end,'destination',private.military_label(f.destination_id,e),'own_location',exists(select 1 from public.planets p where p.id=f.planet_id and owner_empire_id=e))) from private.fleets f where f.empire_id=e and status in ('stationed','transit')),'[]'::jsonb),
 'jobs',coalesce((select jsonb_agg(to_jsonb(j)||jsonb_build_object('planet',private.military_label(j.planet_id,e)) order by finishes_at) from private.ship_jobs j where empire_id=e and completed_at is null and cancelled_at is null),'[]'::jsonb),
 'reports',coalesce((select jsonb_agg(q order by occurred_at desc) from (select r.id,r.event,r.occurred_at,r.details,private.military_label(r.planet_id,e) planet from private.battle_reports r where empire_id=e order by occurred_at desc limit 100)q),'[]'::jsonb),
 'presence',coalesce((select jsonb_agg(to_jsonb(q)) from (select p.id,p.race||'_'||p.resource appearance,private.military_label(p.id,e) name,sum(f.ground_soldiers)::int soldiers,sum(f.soldiers)::int embarked,sum(f.scouts+f.bombers+f.fighters)::int ships,bool_or(f.mission='attack') attacking from private.fleets f join public.planets p on p.id=f.planet_id where f.empire_id=e and f.status='stationed' and p.owner_empire_id is distinct from e and f.scouts+f.bombers+f.fighters+f.soldiers+f.ground_soldiers>0 group by p.id)q),'[]'::jsonb)) into r;
 return r;
end $$;

create function private.guard_trade_siege() returns trigger language plpgsql set search_path='' as $$begin
 if old.status in ('active','pending') and (new.status in ('cancelled','declined') or new.quantity<old.quantity) and (private.ground_superiority(old.planet_a,now()) or private.ground_superiority(old.planet_b,now())) then raise exception 'Liaison verrouillée : contrôle planétaire contesté.';end if;return new;end $$;
create trigger guard_trade_siege before update on private.trade_links for each row execute function private.guard_trade_siege();


create or replace function private.planet_daily_rates(p_id uuid)
returns table(civil numeric,trade numeric,trade_cost numeric,military numeric,fleet numeric)
language sql stable set search_path='' as $$
 select p.population*.02*(case when p.resource='aurite' then 1.15 else 1 end),
 coalesce(t.cost,0)+(coalesce(t.gross,0)-coalesce(t.cost,0))*1.075*private.civilization_trade_multiplier(p.civilization)*(case when p.resource='aurite' then 1.15 else 1 end),
 coalesce(t.cost,0),p.soldiers*2::numeric,(p.scouts::numeric*20+p.bombers::numeric*60+p.fighters::numeric*80)
 from public.planets p left join lateral(
 select sum(l.quantity*1500)::numeric gross,sum(l.quantity*least(l.distance,1000))::numeric cost
 from private.trade_links l where l.status='active' and not exists(select 1 from public.planets b where b.id in(l.planet_a,l.planet_b) and (b.blockaded or b.trade_resumes_at>coalesce(nullif(current_setting('lw.rate_at',true),'')::timestamptz,now()))) and(l.planet_a=p.id or l.planet_b=p.id)
 ) t on true where p.id=p_id;
$$;

create or replace function private.economy_process_base(p_now timestamptz default now())
returns void language plpgsql security definer set search_path='' as $$
#variable_conflict use_column
declare v_id uuid; v_clock private.economy_clock%rowtype; v_end timestamptz;
 v_until timestamptz; v_cursor timestamptz; v_limit timestamptz;
begin
 for v_id in select season_id from private.economy_clock where enabled order by season_id loop
   perform 1 from public.seasons where id=v_id for update;
   select * into v_clock from private.economy_clock where season_id=v_id for update;
   select ends_at into v_end from public.seasons where id=v_id;
   v_limit:=least(p_now,v_end);v_cursor:=v_clock.last_accrued_at;
   if v_limit>v_cursor then
   loop
     v_until:=least(v_limit,v_clock.next_payout_at,coalesce((select min(trade_resumes_at) from public.planets where season_id=v_id and trade_resumes_at>v_cursor and trade_resumes_at<'infinity'),v_limit));
     perform set_config('lw.rate_at',v_cursor::text,true);
     insert into private.economy_accruals(empire_id,planet_id,season_id,civil,trade,trade_cost,military,fleet)
     select empire_id,planet_id,v_id,sum(civil),sum(trade),sum(trade_cost),sum(military),sum(fleet) from (
     select p.owner_empire_id empire_id,p.id planet_id,
       r.civil*d.seconds/86400 civil,r.trade*d.seconds/86400 trade,r.trade_cost*d.seconds/86400 trade_cost,r.military*d.seconds/86400 military,r.fleet*d.seconds/86400 fleet
     from public.planets p cross join lateral private.planet_daily_rates(p.id) r
     cross join lateral(select greatest(0,extract(epoch from(v_until-greatest(v_cursor,p.created_at)))) seconds) d
     where p.season_id=v_id and p.owner_empire_id is not null
     union all
     select f.empire_id,f.supply_planet,0,0,0,(f.soldiers::numeric+f.ground_soldiers)*2*d.seconds/86400,
       (f.scouts::numeric*20+f.bombers::numeric*60+f.fighters::numeric*80)*d.seconds/86400
     from private.fleets f cross join lateral(select greatest(0,extract(epoch from(v_until-greatest(v_cursor,f.created_at)))) seconds) d
     where f.season_id=v_id and f.status in ('stationed','transit')
     ) costs group by empire_id,planet_id
     on conflict(empire_id,planet_id) do update set
       civil=private.economy_accruals.civil+excluded.civil,
       trade=private.economy_accruals.trade+excluded.trade,
       trade_cost=private.economy_accruals.trade_cost+excluded.trade_cost,
       military=private.economy_accruals.military+excluded.military,
       fleet=private.economy_accruals.fleet+excluded.fleet;
     if v_until=v_clock.next_payout_at or v_until=v_end then
       with booked as(
         insert into private.economy_ledger(empire_id,planet_id,payout_at,civil,trade,trade_cost,military,fleet,net)
         select empire_id,planet_id,v_until,floor(civil),floor(trade),floor(trade_cost),floor(military),floor(fleet),
           floor(civil)+floor(trade)-floor(trade_cost)-floor(military)-floor(fleet)
         from private.economy_accruals where season_id=v_id
         on conflict(empire_id,planet_id,payout_at) do nothing returning empire_id,net
       ),totals as(select empire_id,sum(net)::bigint net from booked group by empire_id)
       update public.empires e set
         treasury=greatest(0,e.treasury-e.maintenance_debt+t.net),
         maintenance_debt=greatest(0,-(e.treasury-e.maintenance_debt+t.net))
       from totals t where e.id=t.empire_id;
       update private.economy_accruals set civil=civil-floor(civil),trade=trade-floor(trade),
         trade_cost=trade_cost-floor(trade_cost),military=military-floor(military),fleet=fleet-floor(fleet)
       where season_id=v_id;
       v_clock.next_payout_at:=v_clock.next_payout_at+interval '8 hours';
     end if;
     v_cursor:=v_until;
     exit when v_cursor>=v_limit;
   end loop;
   update private.economy_clock set last_accrued_at=v_limit,next_payout_at=v_clock.next_payout_at where season_id=v_id;
   end if;
   -- Requests reserve both ends for at most 24 hours. No income while pending.
   update private.trade_links set status='expired',closed_at=p_now where season_id=v_id and status='pending' and expires_at<=p_now;
   -- Turning auto-accept back on also accepts existing unexpired incoming requests.
   update private.trade_links l set status='active',activated_at=p_now,expires_at=null
     from public.planets p where l.target_planet=p.id and p.auto_trade
       and l.season_id=v_id and l.status='pending' and l.expires_at>p_now;
 end loop;
 perform set_config('lw.rate_at','',true);
end $$;

create or replace function private.trade_dashboard(p_planet_id uuid) returns jsonb language plpgsql security definer set search_path='' as $$
declare r jsonb;dest jsonb;links jsonb;reserved integer;v_civ integer;v_resource text;blocked boolean;
begin
 r:=private.trade_dashboard_base(p_planet_id);
 select blockaded or trade_resumes_at>now() into blocked from public.planets where id=p_planet_id;
 select civilization,resource into v_civ,v_resource from public.planets where id=p_planet_id;
 select coalesce(jsonb_agg(d.value||jsonb_build_object('blocked',blocked or p.blockaded or p.trade_resumes_at>now(),'net_per_capacity',case when blocked or p.blockaded or p.trade_resumes_at>now() then 0 else (d.value->>'net_per_capacity')::numeric end,'name',p.name,'civilization',p.civilization,'resource',p.resource,'available',greatest(0,p.trade_capacity-private.trade_used(p.id))) order by d.position),'[]'::jsonb)
 into dest from jsonb_array_elements(r->'destinations') with ordinality d(value,position) join public.planets p on p.id=(d.value->>'id')::uuid where p.resource<>v_resource;
 select coalesce(jsonb_agg(z.value||jsonb_build_object('blocked',blocked or p.blockaded or p.trade_resumes_at>now(),'net_daily',case when blocked or p.blockaded or p.trade_resumes_at>now() then 0 else (z.value->>'net_daily')::numeric end,'name',p.name,'civilization',p.civilization,'resource',p.resource,'available',greatest(0,p.trade_capacity-private.trade_used(p.id)),
 'race',p.race,'population',p.population,'appearance',p.race||'_'||p.resource,
 'increase',case when i.id is null then null else jsonb_build_object('quantity',i.quantity,'expires_at',i.expires_at,'can_review',i.requester_planet<>p_planet_id) end) order by z.value->>'created_at' desc),'[]'::jsonb)
 into links from jsonb_array_elements(r->'links') z join public.planets p on p.id=(z.value->>'other_id')::uuid
 left join private.trade_increases i on i.link_id=(z.value->>'id')::uuid and i.status='pending' and i.expires_at>now() and z.value->>'status'='active';
 select coalesce(sum(i.quantity),0)::integer into reserved from private.trade_increases i join private.trade_links l on l.id=i.link_id where i.status='pending' and i.expires_at>now() and l.status='active' and(l.planet_a=p_planet_id or l.planet_b=p_planet_id);
 r:=jsonb_set(r,'{planet,reserved}',to_jsonb((r#>>'{planet,reserved}')::integer+reserved));
 r:=jsonb_set(r,'{planet,civilization}',to_jsonb(v_civ));
 r:=jsonb_set(r,'{planet,resource}',to_jsonb(v_resource));
 return r||jsonb_build_object('destinations',dest,'links',links);
end $$;

revoke all on function private.travel_seconds(double precision),private.fleet_position(private.fleets,timestamptz),private.same_clan(uuid,uuid),private.fortification(public.planets,timestamptz),private.ground_superiority(uuid,timestamptz),private.sync_planet_war(uuid,timestamptz),private.capture_military_state(),private.guard_trade_siege() from public,anon,authenticated;
