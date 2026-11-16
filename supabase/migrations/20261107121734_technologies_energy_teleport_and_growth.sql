-- Settle the old rate before applying the 7.5% net commercial uplift.
select private.economy_process();
create or replace function private.planet_daily_rates(p_id uuid)
returns table(civil numeric,trade numeric,trade_cost numeric,military numeric,fleet numeric)
language sql stable set search_path='' as $$
 select p.population*.02*(case when p.resource='aurite' then 1.15 else 1 end),
 coalesce(t.cost,0)+(coalesce(t.gross,0)-coalesce(t.cost,0))*1.075*private.civilization_trade_multiplier(p.civilization)*(case when p.resource='aurite' then 1.15 else 1 end),
 coalesce(t.cost,0),p.soldiers*2::numeric,(p.scouts::numeric*20+p.bombers::numeric*60+p.fighters::numeric*80)
 from public.planets p left join lateral(
 select sum(l.quantity*1500)::numeric gross,sum(l.quantity*least(l.distance,1000))::numeric cost
 from private.trade_links l where l.status='active' and(l.planet_a=p.id or l.planet_b=p.id)
 ) t on true where p.id=p_id;
$$;

create or replace function private.trade_dashboard_base(p_planet_id uuid) returns jsonb language plpgsql security definer set search_path='' as $$
declare v_player uuid:=private.active_player_id();v_planet public.planets%rowtype;v_bonus numeric;v_result jsonb;
begin
 select * into v_planet from public.planets where id=p_planet_id and owner_empire_id=v_player;
 if not found then raise exception 'Planète inaccessible.' using errcode='42501'; end if;
 perform 1 from public.seasons where id=v_planet.season_id for update;
 perform private.economy_process();
 -- Reload after settlement / automatic acceptance.
 select * into v_planet from public.planets where id=p_planet_id and owner_empire_id=v_player;
 v_bonus:=1.075*(case when v_planet.resource='aurite' then 1.15 else 1 end)*private.civilization_trade_multiplier(v_planet.civilization);
 select jsonb_build_object('enabled',(select enabled from private.economy_clock where season_id=v_planet.season_id),
 'planet',jsonb_build_object('id',v_planet.id,'name',v_planet.name,'capacity',v_planet.trade_capacity,'auto_trade',v_planet.auto_trade,
 'occupied',coalesce((select sum(quantity) from private.trade_links where (planet_a=v_planet.id or planet_b=v_planet.id) and status='active'),0),
 'reserved',coalesce((select sum(quantity) from private.trade_links where (planet_a=v_planet.id or planet_b=v_planet.id) and status='pending'),0)),
 'prices',coalesce((select jsonb_agg(private.capacity_price(n) order by n) from generate_series(v_planet.trade_capacity+1,200) n),'[]'::jsonb),
 'destinations',coalesce((select jsonb_agg(jsonb_build_object('id',s.id,'name',s.designation,'clan_name',s.clan_name,'is_own',s.is_own,
 'distance',round(d.distance,2),'net_per_capacity',round((1500-least(d.distance,1000))*v_bonus,2),
 'distance_cost',round(least(d.distance,1000),2)) order by d.distance)
 from private.galaxy_signals() s cross join lateral(
 select round(sqrt(power(v_planet.x-s.x,2)+power(v_planet.y-s.y,2))::numeric,4) distance) d where s.id<>v_planet.id),'[]'::jsonb),
 'links',coalesce((select jsonb_agg(jsonb_build_object('id',l.id,'quantity',l.quantity,'status',l.status,'created_at',l.created_at,
 'expires_at',l.expires_at,'other_id',s.id,'name',s.designation,'clan_name',s.clan_name,'distance',round(l.distance,2),
 'net_daily',round(l.quantity*(1500-least(l.distance,1000))*v_bonus,2),
 'can_review',l.status='pending' and l.target_planet=v_planet.id) order by l.created_at desc)
 from private.trade_links l join private.galaxy_signals() s on s.id=case when l.planet_a=v_planet.id then l.planet_b else l.planet_a end
 where (l.planet_a=v_planet.id or l.planet_b=v_planet.id) and l.status in ('pending','active')),'[]'::jsonb))
 into v_result;
 return v_result;
end $$;

create table private.player_technologies(
 empire_id uuid primary key references public.empires(id) on delete cascade,
 energy_unlocked_at timestamptz,teleport_unlocked_at timestamptz
);
alter table private.player_technologies enable row level security;
revoke all on private.player_technologies from public,anon,authenticated;
create table private.technology_commands(
 empire_id uuid not null references public.empires(id) on delete cascade,
 request_id uuid not null,payload jsonb not null,result jsonb not null,
 secret_hash text,primary key(empire_id,request_id)
);
alter table private.technology_commands enable row level security;
revoke all on private.technology_commands from public,anon,authenticated;

alter table public.planets add column development_last_at timestamptz not null default now();
alter table public.planets add column population_fraction numeric not null default 0 check(population_fraction>=0 and population_fraction<1);
alter table public.planets add column energy_fraction numeric not null default 0 check(energy_fraction>=0 and energy_fraction<1);
alter table public.planets alter column energy_max set default 10;
update public.planets set energy_max=greatest(10,energy) where energy_max=100;
alter table public.planets add constraint energy_storage_limit check(energy_max between 10 and 100);
create function private.energy_capacity_price(p_rank int) returns bigint language sql immutable strict set search_path='' as $$
 select case when p_rank between 11 and 100 then round(5000*power(1.055::numeric,p_rank-11))::bigint else null end;
$$;
create function private.planet_at_war(p_planet uuid) returns boolean language sql stable set search_path='' as $$
 select exists(select 1 from private.fleets where planet_id=p_planet and status='stationed' and mission='attack' and scouts::bigint+bombers+fighters+ground_soldiers+soldiers>0);
$$;
create function private.population_growth_state(p_planet uuid) returns jsonb language plpgsql stable set search_path='' as $$
declare p public.planets%rowtype;war boolean;nearby boolean;occupancy numeric;rate numeric;begin
 select * into p from public.planets where id=p_planet;
 war:=private.planet_at_war(p.id);
 select coalesce(bool_or(private.planet_at_war(n.id)),false) into nearby from(select id from public.planets where season_id=p.season_id and id<>p.id order by power(x-p.x,2)+power(y-p.y,2),id limit 5)n;
 select case when p.trade_capacity=0 then 0 else least(1,coalesce(sum(quantity),0)::numeric/p.trade_capacity) end into occupancy from private.trade_links where status='active' and (planet_a=p.id or planet_b=p.id);
 rate:=case when p.owner_empire_id is null or war then 0 else .005*(case when p.governance='conseil' then 1.2 else .8 end)*(1+.25*occupancy)*(case when nearby then .5 else 1 end) end;
 return jsonb_build_object('daily_rate',rate,'daily_people',p.population*rate,'war',war,'nearby_war',nearby,'trade_occupancy',occupancy);
end $$;
create function private.advance_planet_development(p_season uuid,p_at timestamptz) returns void language plpgsql set search_path='' as $$
declare p public.planets%rowtype;seconds numeric;growth numeric;energy_amount numeric;g jsonb;has_energy boolean;new_energy int;begin
 delete from private.teleport_attempts where attempted_at<least(p_at,now())-interval '1 day';
 for p in select * from public.planets where season_id=p_season and owner_empire_id is not null and development_last_at<p_at order by id for update loop
 seconds:=greatest(0,extract(epoch from(p_at-p.development_last_at)));g:=private.population_growth_state(p.id);
 growth:=p.population_fraction+p.population*(g->>'daily_rate')::numeric*seconds/86400;
 select exists(select 1 from private.player_technologies where empire_id=p.owner_empire_id and energy_unlocked_at is not null) into has_energy;
 if has_energy and p.energy<p.energy_max then
  energy_amount:=p.energy_fraction+seconds/21600;new_energy:=least(p.energy_max,p.energy+floor(energy_amount)::int);
  update public.planets set energy=new_energy,energy_fraction=case when new_energy=energy_max then 0 else energy_amount-floor(energy_amount) end where id=p.id;
 else update public.planets set energy_fraction=0 where id=p.id;end if;
 update public.planets set population=population+floor(growth)::bigint,population_fraction=growth-floor(growth),development_last_at=p_at where id=p.id;
 end loop;
end $$;
create function private.development_ownership() returns trigger language plpgsql set search_path='' as $$
begin
 if new.owner_empire_id is distinct from old.owner_empire_id then
  new.development_last_at:=coalesce(nullif(current_setting('lw.development_at',true),'')::timestamptz,now());new.population_fraction:=0;new.energy_fraction:=0;
  if old.owner_empire_id is null and exists(select 1 from private.player_technologies where empire_id=new.owner_empire_id and energy_unlocked_at is not null) then new.energy:=greatest(new.energy,10);end if;
 end if;return new;
end $$;
create trigger development_ownership before update of owner_empire_id on public.planets for each row execute function private.development_ownership();
revoke all on function private.energy_capacity_price(int),private.planet_at_war(uuid),private.population_growth_state(uuid),private.advance_planet_development(uuid,timestamptz),private.development_ownership() from public,anon,authenticated;
create or replace function private.military_process(p_now timestamptz default now()) returns void language plpgsql security definer set search_path='' as $$
#variable_conflict use_column
declare c private.military_clock%rowtype;s record;v_at timestamptz;v_limit timestamptz;j record;f record;b record;p public.planets%rowtype;amount numeric;n int;
begin
 for s in select id,ends_at from public.seasons where status='alpha' order by id loop
 perform 1 from public.seasons where id=s.id for update;
 select * into c from private.military_clock where season_id=s.id for update;if not found then continue;end if;
 v_limit:=least(p_now,s.ends_at);
 loop
   select least(c.next_tick,coalesce((select min(cj.finishes_at) from private.civilization_jobs cj join public.planets cp on cp.id=cj.planet_id where cp.season_id=s.id and cj.completed_at is null and cj.cancelled_at is null),'infinity'),coalesce((select min(finishes_at) from private.ship_jobs j join public.planets p on p.id=j.planet_id where p.season_id=s.id and completed_at is null and cancelled_at is null),'infinity'),coalesce((select min(arrives_at) from private.fleets where season_id=s.id and status='transit'),'infinity')) into v_at;
   exit when v_at>v_limit;
   perform private.economy_process_base(v_at);
   perform private.advance_planet_development(s.id,v_at);
   perform set_config('lw.development_at',v_at::text,true);
   for j in select cj.* from private.civilization_jobs cj join public.planets cp on cp.id=cj.planet_id where cp.season_id=s.id and cj.completed_at is null and cj.cancelled_at is null and cj.finishes_at<=v_at order by cj.finishes_at,cj.target_level loop
    update public.planets set civilization=j.target_level where id=j.planet_id and owner_empire_id=j.empire_id and civilization=j.target_level-1;
    if found then update private.civilization_jobs set completed_at=v_at where id=j.id;
    else update private.civilization_jobs set cancelled_at=v_at where id=j.id;end if;
   end loop;
   for j in select j.* from private.ship_jobs j join public.planets p on p.id=j.planet_id where p.season_id=s.id and completed_at is null and cancelled_at is null and finishes_at<=v_at order by finishes_at,j.id loop
    update public.planets set factories=factories+case when j.kind='factory' then 1 else 0 end,scouts=scouts+case when j.kind='scout' then 1 else 0 end,bombers=bombers+case when j.kind='bomber' then 1 else 0 end,fighters=fighters+case when j.kind='fighter' then 1 else 0 end where id=j.planet_id and owner_empire_id=j.empire_id;
    update private.ship_jobs set completed_at=v_at,cancelled_at=case when not exists(select 1 from public.planets where id=j.planet_id and owner_empire_id=j.empire_id) then v_at end where id=j.id;
   end loop;
   for f in select * from private.fleets where season_id=s.id and status='transit' and arrives_at<=v_at order by arrives_at,id loop
    update private.fleets set status='stationed',planet_id=destination_id,lands_at=arrives_at+interval '1 hour',mission=case when exists(select 1 from public.planets where id=f.destination_id and owner_empire_id=f.empire_id) then 'defend' else mission end where id=f.id;
    insert into private.battle_reports(empire_id,planet_id,occurred_at,event,details) values(f.empire_id,f.destination_id,v_at,'arrival',jsonb_build_object('fleet',f.name,'lands_at',f.arrives_at+interval '1 hour','mission',f.mission));
   end loop;
   if v_at=c.next_tick then
    for p in select * from public.planets where season_id=s.id and owner_empire_id is not null and recruitment_enabled and soldiers<greatest(1,population/1000) loop
      amount:=p.recruitment_fraction+private.recruitment_daily(p)/24;n:=least(greatest(1,p.population/1000)-p.soldiers,floor(amount)::bigint)::int;
      update public.planets set soldiers=soldiers+n,recruitment_fraction=amount-floor(amount) where id=p.id;
      if n>0 then insert into private.player_merit(empire_id,produced_soldiers) values(p.owner_empire_id,n) on conflict(empire_id) do update set produced_soldiers=private.player_merit.produced_soldiers+excluded.produced_soldiers;end if;
    end loop;
    update private.fleets set ground_soldiers=ground_soldiers+soldiers,soldiers=0,lands_at=null where season_id=s.id and status='stationed' and lands_at<=v_at;
    for b in select distinct planet_id id from private.fleets where season_id=s.id and status='stationed' and mission='attack' loop perform private.resolve_battle(b.id,v_at);end loop;
    c.next_tick:=c.next_tick+interval '1 hour';
   end if;
 end loop;
 perform private.economy_process_base(v_limit);
 perform private.advance_planet_development(s.id,v_limit);
 perform set_config('lw.development_at','',true);
 update private.military_clock set last_processed=v_limit,next_tick=c.next_tick where season_id=s.id;
 perform private.refresh_ranks(s.id);
 end loop;
end $$;

create table private.planet_teleport_access(
 planet_id uuid primary key references public.planets(id) on delete cascade,
 password_hash text not null,changed_at timestamptz not null default now()
);
create table private.teleport_attempts(
 id bigint generated always as identity primary key,
 empire_id uuid not null references public.empires(id) on delete cascade,
 planet_id uuid not null references public.planets(id) on delete cascade,
 attempted_at timestamptz not null default clock_timestamp()
);
create index teleport_attempts_actor on private.teleport_attempts(empire_id,attempted_at desc);
create index teleport_attempts_planet on private.teleport_attempts(planet_id,attempted_at desc);
create index teleport_attempts_expiry on private.teleport_attempts(attempted_at);
alter table private.planet_teleport_access enable row level security;
alter table private.teleport_attempts enable row level security;
revoke all on private.planet_teleport_access,private.teleport_attempts from public,anon,authenticated;
alter table public.planets add column teleport_ready_at timestamptz not null default now();
create function private.teleport_capture_network() returns trigger language plpgsql set search_path='' as $$
begin
 if new.owner_empire_id is distinct from old.owner_empire_id then
  new.teleport_ready_at:=coalesce(nullif(current_setting('lw.development_at',true),'')::timestamptz,now())+make_interval(hours=>4*(1+(select count(*)::int from public.planets where owner_empire_id=new.owner_empire_id)));
 end if;return new;
end $$;
create function private.clear_captured_teleport_access() returns trigger language plpgsql set search_path='' as $$
begin if new.owner_empire_id is distinct from old.owner_empire_id then delete from private.planet_teleport_access where planet_id=new.id;end if;return new;end $$;
create trigger teleport_capture_network before update of owner_empire_id on public.planets for each row execute function private.teleport_capture_network();
create trigger clear_captured_teleport_access after update of owner_empire_id on public.planets for each row execute function private.clear_captured_teleport_access();
revoke all on function private.teleport_capture_network(),private.clear_captured_teleport_access() from public,anon,authenticated;

create function private.technology_command(p_action text,p_args jsonb,p_request_id uuid) returns jsonb language plpgsql security definer set search_path='' as $$
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
  select coalesce(sum(ground_soldiers),0)+(case when v_p.owner_empire_id=v_e then v_p.soldiers else 0 end) into v_available from private.fleets where empire_id=v_e and planet_id=v_origin and status='stationed';
  if v_q>v_available then raise exception 'Soldats au sol disponibles insuffisants.';end if;
  v_foreign:=case when v_p.owner_empire_id<>v_e then v_p.id when v_t.owner_empire_id<>v_e then v_t.id else null end;
  if v_foreign is not null then
   select clan_id into v_clan from private.clan_memberships where empire_id=v_e;
   select clan_id into v_other_clan from private.clan_memberships where empire_id=case when v_p.owner_empire_id<>v_e then v_p.owner_empire_id else v_t.owner_empire_id end;
   v_allowed:=v_clan is not null and v_clan=v_other_clan;
   if not v_allowed then
    if (select count(*) from private.teleport_attempts where empire_id=v_e and attempted_at>clock_timestamp()-interval '1 minute')>=10 or (select count(*) from private.teleport_attempts where planet_id=v_foreign and attempted_at>clock_timestamp()-interval '1 minute')>=20 then return jsonb_build_object('ok',false,'error','Trop de tentatives. Réessayez dans une minute.');end if;
    insert into private.teleport_attempts(empire_id,planet_id) values(v_e,v_foreign);
    select password_hash into v_hash from private.planet_teleport_access where planet_id=v_foreign;
    if v_hash is null or v_code='' or extensions.crypt(v_code,v_hash)<>v_hash then return jsonb_build_object('ok',false,'error','Accès de téléportation refusé.');end if;
   end if;
  end if;
  update public.planets set energy=energy-v_cost where id=v_energy_planet;
  v_remaining:=v_q;
  if v_p.owner_empire_id=v_e then
   v_take:=least(v_p.soldiers,v_remaining);
   if v_take>0 then
    update public.planets set soldiers=soldiers-v_take where id=v_p.id;
    insert into private.fleets(empire_id,season_id,name,race,supply_planet,planet_id,origin_id,mission,ground_soldiers) values(v_e,v_s,'Renforts téléportés',v_p.race,v_energy_planet,v_t.id,v_p.id,'defend',v_take);
    v_remaining:=v_remaining-v_take;
   end if;
  end if;
  for v_group in select * from private.fleets where empire_id=v_e and planet_id=v_p.id and status='stationed' and ground_soldiers>0 order by id for update loop
   exit when v_remaining=0;v_take:=least(v_group.ground_soldiers,v_remaining);
   update private.fleets set ground_soldiers=ground_soldiers-v_take where id=v_group.id;
   insert into private.fleets(empire_id,season_id,name,race,supply_planet,planet_id,origin_id,mission,ground_soldiers) values(v_e,v_s,'Renforts téléportés',v_group.race,v_energy_planet,v_t.id,v_p.id,'defend',v_take);
   v_remaining:=v_remaining-v_take;
  end loop;
  if v_remaining<>0 then raise exception 'Soldats disponibles modifiés. Actualisez.';end if;
  update private.fleets set status='disbanded' where empire_id=v_e and planet_id=v_p.id and status='stationed' and scouts::bigint+bombers+fighters+soldiers+ground_soldiers=0;
  insert into private.battle_reports(empire_id,planet_id,occurred_at,event,details) values(v_e,v_t.id,v_at,'arrival',jsonb_build_object('fleet','Renforts téléportés','mission','defend','lands_at',v_at,'teleport',true,'soldiers',v_q));
  v_result:=jsonb_build_object('ok',true,'quantity',v_q,'energy_cost',v_cost);
 else raise exception 'Action technologique inconnue.';end if;
 if v_code<>'' and v_secret is null then v_secret:=extensions.crypt(v_code,extensions.gen_salt('bf',10));end if;
 insert into private.technology_commands(empire_id,request_id,payload,result,secret_hash) values(v_e,p_request_id,v_payload,v_result,v_secret);
 delete from private.teleport_attempts where attempted_at<clock_timestamp()-interval '1 day';
 return v_result;
end $$;
create function public.technology_command(p_action text,p_args jsonb,p_request_id uuid) returns jsonb language sql security invoker set search_path='' as $$select private.technology_command(p_action,p_args,p_request_id);$$;
revoke all on function private.technology_command(text,jsonb,uuid),public.technology_command(text,jsonb,uuid) from public,anon,authenticated;
grant execute on function private.technology_command(text,jsonb,uuid),public.technology_command(text,jsonb,uuid) to authenticated;

create function private.technology_dashboard() returns jsonb language plpgsql security definer set search_path='' as $$
declare v_e uuid;v_s uuid;v_clan uuid;v_energy boolean;v_teleport boolean;v_result jsonb;begin
 select id into v_s from public.seasons where status='alpha' for update;v_e:=private.active_player_id();perform private.economy_process();
 select exists(select 1 from private.player_technologies where empire_id=v_e and energy_unlocked_at is not null),exists(select 1 from private.player_technologies where empire_id=v_e and teleport_unlocked_at is not null) into v_energy,v_teleport;
 select clan_id into v_clan from private.clan_memberships where empire_id=v_e;
 select jsonb_build_object('server_now',now(),'energy_unlocked',v_energy,'teleport_unlocked',v_teleport,'energy_cost',150000,'teleport_cost',300000,
 'energy_prices',(select jsonb_object_agg(n::text,private.energy_capacity_price(n)) from generate_series(11,100)n),
 'planets',coalesce((select jsonb_agg(to_jsonb(p)||jsonb_build_object('growth',private.population_growth_state(p.id),'code_configured',exists(select 1 from private.planet_teleport_access where planet_id=p.id),
 'next_recharge_at',case when v_energy and p.energy<p.energy_max then p.development_last_at+make_interval(secs=>((1-p.energy_fraction)*21600)::double precision) end) order by p.serial) from public.planets p where owner_empire_id=v_e),'[]'),
 'origins',coalesce((select jsonb_agg(jsonb_build_object('id',p.id,'name',p.name,'x',p.x,'y',p.y,'is_own',p.owner_empire_id=v_e,'energy',case when p.owner_empire_id=v_e then p.energy else null end,
 'available_soldiers',(case when p.owner_empire_id=v_e then p.soldiers else 0 end)+coalesce((select sum(ground_soldiers) from private.fleets where empire_id=v_e and planet_id=p.id and status='stationed'),0),
 'network_ready_at',p.teleport_ready_at,'access',case when p.owner_empire_id=v_e then 'own' when v_clan is not null and exists(select 1 from private.clan_memberships where empire_id=p.owner_empire_id and clan_id=v_clan) then 'clan' else 'password' end) order by p.serial)
 from public.planets p where p.season_id=v_s and (p.owner_empire_id=v_e or exists(select 1 from private.fleets where empire_id=v_e and planet_id=p.id and status='stationed' and ground_soldiers>0)) and p.owner_empire_id is not null and (p.owner_empire_id=v_e or exists(select 1 from private.player_technologies where empire_id=p.owner_empire_id and teleport_unlocked_at is not null))),'[]'),
 'targets',coalesce((select jsonb_agg(jsonb_build_object('id',p.id,'name',p.name,'x',p.x,'y',p.y,'is_own',p.owner_empire_id=v_e,'energy',case when p.owner_empire_id=v_e then p.energy else null end,'network_ready_at',p.teleport_ready_at,
 'access',case when p.owner_empire_id=v_e then 'own' when v_clan is not null and exists(select 1 from private.clan_memberships where empire_id=p.owner_empire_id and clan_id=v_clan) then 'clan' else 'password' end) order by p.serial)
 from public.planets p where p.season_id=v_s and v_teleport and exists(select 1 from private.player_technologies where empire_id=p.owner_empire_id and teleport_unlocked_at is not null)
 and (p.owner_empire_id=v_e or (v_clan is not null and exists(select 1 from private.clan_memberships where empire_id=p.owner_empire_id and clan_id=v_clan)) or exists(select 1 from private.planet_teleport_access where planet_id=p.id))),'[]')) into v_result;
 return v_result;end $$;
create function public.technology_dashboard() returns jsonb language sql security invoker set search_path='' as $$select private.technology_dashboard();$$;
revoke all on function private.technology_dashboard(),public.technology_dashboard() from public,anon,authenticated;
grant execute on function private.technology_dashboard(),public.technology_dashboard() to authenticated;
