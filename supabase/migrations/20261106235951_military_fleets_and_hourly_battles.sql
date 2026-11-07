-- Server-authoritative alpha military system. No existing units or balances are reset.
alter table public.planets add column factories integer not null default 5 check(factories between 5 and 200),
 add column recruitment_enabled boolean not null default true,
 add column recruitment_fraction numeric not null default 0 check(recruitment_fraction>=0 and recruitment_fraction<1);
create table private.military_clock(season_id uuid primary key references public.seasons(id),last_processed timestamptz not null,next_tick timestamptz not null);
insert into private.military_clock select id,now(),date_trunc('hour',now())+interval '1 hour' from public.seasons where status='alpha';
create table private.ship_jobs(id uuid primary key default gen_random_uuid(),empire_id uuid not null references public.empires(id) on delete cascade,planet_id uuid not null references public.planets(id) on delete cascade,kind text not null check(kind in ('factory','scout','bomber','fighter')),cost bigint not null check(cost>0),started_at timestamptz not null,finishes_at timestamptz not null,completed_at timestamptz,cancelled_at timestamptz);
create index ship_jobs_due on private.ship_jobs(finishes_at) where completed_at is null and cancelled_at is null;
create index ship_jobs_owner on private.ship_jobs(empire_id,planet_id);
create table private.fleets(id uuid primary key default gen_random_uuid(),empire_id uuid not null references public.empires(id) on delete cascade,season_id uuid not null references public.seasons(id),name text not null check(char_length(name) between 1 and 40),race text not null check(race in ('vael','khar','elys')),supply_planet uuid not null references public.planets(id) on delete cascade,planet_id uuid references public.planets(id) on delete cascade,origin_id uuid not null references public.planets(id) on delete cascade,destination_id uuid references public.planets(id) on delete cascade,mission text not null default 'defend' check(mission in ('defend','attack')),status text not null default 'stationed' check(status in ('stationed','transit','destroyed','disbanded')),scouts integer not null default 0 check(scouts>=0),bombers integer not null default 0 check(bombers>=0),fighters integer not null default 0 check(fighters>=0),soldiers integer not null default 0 check(soldiers>=0),ground_soldiers integer not null default 0 check(ground_soldiers>=0),departed_at timestamptz,arrives_at timestamptz,lands_at timestamptz,created_at timestamptz not null default now(),check(soldiers<=10*(bombers+fighters)),check((status='transit' and planet_id is null and destination_id is not null and ground_soldiers=0) or status<>'transit'));
create index fleets_owner on private.fleets(empire_id,status);
create index fleets_location on private.fleets(planet_id,status);
create index fleets_arrivals on private.fleets(arrives_at) where status='transit';
create index fleets_supply on private.fleets(supply_planet);
create index fleets_origin on private.fleets(origin_id);
create index fleets_destination on private.fleets(destination_id);
create table private.military_commands(empire_id uuid not null references public.empires(id) on delete cascade,request_id uuid not null,payload jsonb not null,result jsonb not null,primary key(empire_id,request_id));
create table private.battle_reports(id uuid primary key default gen_random_uuid(),empire_id uuid not null references public.empires(id) on delete cascade,planet_id uuid not null references public.planets(id) on delete cascade,occurred_at timestamptz not null,event text not null,details jsonb not null);
create index battle_reports_owner on private.battle_reports(empire_id,occurred_at desc);
create index battle_reports_planet on private.battle_reports(planet_id);
create table private.battle_damage(planet_id uuid not null references public.planets(id) on delete cascade,force_id uuid not null,scouts numeric not null default 0,bombers numeric not null default 0,fighters numeric not null default 0,ground numeric not null default 0,primary key(planet_id,force_id));
alter table private.military_clock enable row level security;
alter table private.ship_jobs enable row level security;
alter table private.fleets enable row level security;
alter table private.military_commands enable row level security;
alter table private.battle_reports enable row level security;
alter table private.battle_damage enable row level security;
revoke all on private.military_clock,private.ship_jobs,private.fleets,private.military_commands,private.battle_reports,private.battle_damage from public,anon,authenticated;
create function private.recruitment_daily(p public.planets) returns numeric language sql immutable set search_path='' as $$
 select case when p.owner_empire_id is null or not p.recruitment_enabled or p.soldiers>=greatest(1,p.population/1000) then 0 else 1.5*p.population/1000000*p.civilization*(case when p.resource='biomasse' then 1.15 else 1 end)*(case when p.governance='tyrannie' then 1.2 else .8 end) end;
$$;
create function private.factory_price(p_rank integer) returns bigint language sql immutable strict set search_path='' as $$select ceil(25000*power(greatest(p_rank,6)::numeric/6,1.6))::bigint;$$;
create function private.military_label(p_id uuid,p_empire uuid) returns text language sql stable set search_path='' as $$
 select case when owner_empire_id=p_empire or clan_tag_visible then name else 'Signal '||serial end from public.planets where id=p_id;
$$;
-- Accrue economic time before every military event. Fleet upkeep follows its owner,
-- including in transit, after losing its supply world, and when no world is owned.
alter function private.economy_process(timestamptz) rename to economy_process_base;

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
     v_until:=least(v_limit,v_clock.next_payout_at);
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
end $$;

create function private.resolve_battle(p_planet uuid,p_at timestamptz) returns void language plpgsql set search_path='' as $$
#variable_conflict use_column
declare p public.planets%rowtype;snap jsonb;u record;t record;d private.battle_damage%rowtype;att record;def record;
 enemy record;sr numeric;gr numeric;ls integer;lb integer;lf integer;lg integer;ns integer;nb integer;nf integer;ng integer;nc integer;
 winner uuid;old_owner uuid;visible_ground boolean;my_before jsonb;my_after jsonb;enemy_space jsonb;enemy_ground jsonb;event_name text;
begin
 select * into p from public.planets where id=p_planet for update;
 select jsonb_agg(to_jsonb(q)) into snap from(
 select p.id id,p.owner_empire_id empire_id,'defend'::text side,p.race,p.scouts,p.bombers,p.fighters,p.soldiers ground,0 cargo,true local
 union all select f.id,f.empire_id,f.mission,f.race,f.scouts,f.bombers,f.fighters,f.ground_soldiers,f.soldiers,false from private.fleets f where f.planet_id=p.id and f.status='stationed'
 ) q;
 select sum(scouts*2+bombers*10+fighters*12)::numeric hp,sum((scouts+fighters*8)*(case when race='vael' then 1.15 when race='khar' then .85 else 1 end))::numeric power,sum(ground)::numeric ground,sum(ground*(case when race='khar' then 1.15 when race='vael' then .85 else 1 end))::numeric ground_power,sum(bombers)::numeric bombers into att from jsonb_to_recordset(snap) as x(side text,race text,scouts int,bombers int,fighters int,ground int) where side='attack';
 select sum(scouts*2+bombers*10+fighters*12)::numeric hp,sum((scouts+fighters*8)*(case when race='vael' then 1.15 when race='khar' then .85 else 1 end))::numeric power,sum(ground)::numeric ground,sum(ground*(case when race='khar' then 1.15 when race='vael' then .85 else 1 end))::numeric ground_power,sum(bombers)::numeric bombers into def from jsonb_to_recordset(snap) as x(side text,race text,scouts int,bombers int,fighters int,ground int) where side='defend';
 if coalesce(att.hp,0)+coalesce(att.ground,0)=0 then return;end if;
 if coalesce(def.hp,0)+coalesce(def.ground,0)>0 then
 for u in select * from jsonb_to_recordset(snap) as x(id uuid,empire_id uuid,side text,race text,scouts int,bombers int,fighters int,ground int,cargo int,local boolean) loop
   if u.side='attack' then
     sr:=least(1,coalesce(def.power,0)*.12/greatest(coalesce(att.hp,0),1));
     gr:=least(1,(coalesce(def.ground_power,0)*.12+coalesce(def.bombers,0)*2)/greatest(coalesce(att.ground,0),1));
   else
     sr:=least(1,coalesce(att.power,0)*.12/greatest(coalesce(def.hp,0),1));
     gr:=least(1,(coalesce(att.ground_power,0)*.12+coalesce(att.bombers,0)*2)/greatest(coalesce(def.ground,0),1));
   end if;
   insert into private.battle_damage(planet_id,force_id) values(p.id,u.id) on conflict do nothing;
   select * into d from private.battle_damage where planet_id=p.id and force_id=u.id;
   ls:=least(u.scouts,floor(u.scouts*sr+d.scouts)::int);lb:=least(u.bombers,floor(u.bombers*sr+d.bombers)::int);lf:=least(u.fighters,floor(u.fighters*sr+d.fighters)::int);lg:=least(u.ground,floor(u.ground*gr+d.ground)::int);
   ns:=u.scouts-ls;nb:=u.bombers-lb;nf:=u.fighters-lf;ng:=u.ground-lg;
   nc:=least(10*(nb+nf),floor(u.cargo*(case when u.bombers+u.fighters=0 then 0 else (nb+nf)::numeric/(u.bombers+u.fighters) end))::int);
   update private.battle_damage set scouts=u.scouts*sr+d.scouts-ls,bombers=u.bombers*sr+d.bombers-lb,fighters=u.fighters*sr+d.fighters-lf,ground=u.ground*gr+d.ground-lg where planet_id=p.id and force_id=u.id;
   if u.local then update public.planets set scouts=ns,bombers=nb,fighters=nf,soldiers=ng where id=p.id;
   else update private.fleets set scouts=ns,bombers=nb,fighters=nf,soldiers=nc,ground_soldiers=ng,status=case when ns+nb+nf+ng+nc=0 then 'destroyed' else status end where id=u.id;end if;
 end loop;
 end if;
 select * into p from public.planets where id=p.id;
 if p.scouts+p.bombers+p.fighters+p.soldiers=0 and not exists(select 1 from private.fleets where planet_id=p.id and status='stationed' and mission='defend' and scouts+bombers+fighters+soldiers+ground_soldiers>0) then
   select empire_id into winner from private.fleets where planet_id=p.id and status='stationed' and mission='attack' and ground_soldiers>0 group by empire_id order by sum(ground_soldiers) desc,empire_id limit 1;
   if winner is not null and winner is distinct from p.owner_empire_id and (select count(*) from public.planets where owner_empire_id=winner)<12 then
     old_owner:=p.owner_empire_id;
     update public.planets set owner_empire_id=winner,rename_available=true,clan_tag_visible=false,recruitment_fraction=0 where id=p.id;
     update private.ship_jobs set cancelled_at=p_at where planet_id=p.id and completed_at is null and cancelled_at is null;
     update private.fleets set mission='defend' where planet_id=p.id and status='stationed' and mission='attack';
     event_name:='capture';
   else event_name:='battle';end if;
 else event_name:='battle';end if;
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
create function private.military_process(p_now timestamptz default now()) returns void language plpgsql security definer set search_path='' as $$
#variable_conflict use_column
declare c private.military_clock%rowtype;s record;v_at timestamptz;v_limit timestamptz;j record;f record;b record;p public.planets%rowtype;amount numeric;n int;
begin
 for s in select id,ends_at from public.seasons where status='alpha' order by id loop
 perform 1 from public.seasons where id=s.id for update;
 select * into c from private.military_clock where season_id=s.id for update;if not found then continue;end if;
 v_limit:=least(p_now,s.ends_at);
 loop
   select least(c.next_tick,coalesce((select min(finishes_at) from private.ship_jobs j join public.planets p on p.id=j.planet_id where p.season_id=s.id and completed_at is null and cancelled_at is null),'infinity'),coalesce((select min(arrives_at) from private.fleets where season_id=s.id and status='transit'),'infinity')) into v_at;
   exit when v_at>v_limit;
   perform private.economy_process_base(v_at);
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
    end loop;
    update private.fleets set ground_soldiers=ground_soldiers+soldiers,soldiers=0,lands_at=null where season_id=s.id and status='stationed' and lands_at<=v_at;
    for b in select distinct planet_id id from private.fleets where season_id=s.id and status='stationed' and mission='attack' loop perform private.resolve_battle(b.id,v_at);end loop;
    c.next_tick:=c.next_tick+interval '1 hour';
   end if;
 end loop;
 update private.military_clock set last_processed=v_limit,next_tick=c.next_tick where season_id=s.id;
 end loop;
end $$;
create function private.economy_process(p_now timestamptz default now()) returns void language plpgsql security definer set search_path='' as $$begin perform private.military_process(p_now);perform private.economy_process_base(p_now);end $$;
create function private.military_command(p_action text,p_args jsonb,p_request_id uuid) returns jsonb language plpgsql security definer set search_path='' as $$
#variable_conflict use_column
declare e uuid;s uuid;p public.planets%rowtype;target public.planets%rowtype;f private.fleets%rowtype;prev private.military_commands%rowtype;g record;payload jsonb;r jsonb;pid uuid;fid uuid;kind text;q int;n int;ns int;nb int;nf int;delta int;remaining int;take_n int;cost bigint;hours numeric;distance numeric;v_id uuid;v_at timestamptz:=now();
begin
 select id into s from public.seasons where status='alpha' for update;e:=private.active_player_id();
 if p_request_id is null or p_args is null or jsonb_typeof(p_args)<>'object' then raise exception 'Commande invalide.';end if;
 payload:=jsonb_build_object('action',p_action,'args',p_args);select * into prev from private.military_commands where empire_id=e and request_id=p_request_id;
 if found then if prev.payload<>payload then raise exception 'Identifiant déjà utilisé pour une autre commande.';end if;return prev.result;end if;
 perform private.economy_process();
 pid:=(p_args->>'planet_id')::uuid;fid:=(p_args->>'fleet_id')::uuid;
 if p_action in ('recruitment','factory','ship','assemble','rename') then
 select * into p from public.planets where id=pid and owner_empire_id=e and season_id=s for update;if not found then raise exception 'Planète inaccessible.' using errcode='42501';end if;
 end if;
 if p_action in ('load','dispatch','disband') then
 select * into f from private.fleets where id=fid and empire_id=e and status='stationed' for update;if not found then raise exception 'Flotte indisponible.' using errcode='42501';end if;
 select * into p from public.planets where id=f.planet_id for update;
 end if;
 if p_action='recruitment' then
 if jsonb_typeof(p_args->'enabled') is distinct from 'boolean' then raise exception 'Choix de recrutement invalide.';end if;
 update public.planets set recruitment_enabled=(p_args->>'enabled')::boolean where id=p.id;
 elsif p_action='rename' then
 if not p.rename_available or char_length(btrim(p_args->>'name')) not between 3 and 40 then raise exception 'Renommage indisponible ou nom invalide.';end if;
 update public.planets set name=btrim(p_args->>'name'),rename_available=false where id=p.id;
 elsif p_action in ('factory','ship') then
 if p_action='factory' then
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
 update public.planets set scouts=scouts-ns,bombers=bombers-nb,fighters=fighters-nf where id=p.id;
 insert into private.fleets(empire_id,season_id,name,race,supply_planet,planet_id,origin_id,scouts,bombers,fighters,created_at) values(e,s,btrim(p_args->>'name'),p.race,p.id,p.id,p.id,ns,nb,nf,v_at) returning id into v_id;
 elsif p_action='load' then
 q:=(p_args->>'soldiers')::int;if q is null or q<0 or q>10*(f.bombers+f.fighters) then raise exception 'Capacité de transport dépassée.';end if;
 delta:=q-f.soldiers;
 if delta<0 and f.lands_at is not null and v_at<f.lands_at then raise exception 'Le débarquement doit attendre une heure après l’arrivée.';end if;
 if delta>0 then
  remaining:=delta;
  if p.owner_empire_id=e then take_n:=least(p.soldiers,remaining);update public.planets set soldiers=soldiers-take_n where id=p.id;remaining:=remaining-take_n;end if;
  for g in select * from private.fleets where empire_id=e and planet_id=p.id and status='stationed' and ground_soldiers>0 order by id for update loop
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
 update private.fleets set origin_id=p.id,destination_id=target.id,planet_id=null,status='transit',mission=p_args->>'mission',departed_at=v_at,arrives_at=v_at+make_interval(secs=>greatest(60,ceil(distance/sqrt(2000000)*691200))::double precision),lands_at=null,ground_soldiers=0 where id=f.id;
 elsif p_action='disband' then
 if p.owner_empire_id is distinct from e then raise exception 'Ralliez un monde sous votre contrôle pour dissoudre cette flotte.';end if;
 update public.planets set scouts=scouts+f.scouts,bombers=bombers+f.bombers,fighters=fighters+f.fighters,soldiers=soldiers+f.soldiers+f.ground_soldiers where id=p.id;
 update private.fleets set status='disbanded',scouts=0,bombers=0,fighters=0,soldiers=0,ground_soldiers=0 where id=f.id;
 else raise exception 'Action inconnue.';end if;
 r:=jsonb_build_object('ok',true,'id',coalesce(v_id,fid,pid));insert into private.military_commands values(e,p_request_id,payload,r);return r;
end $$;
create function private.military_dashboard() returns jsonb language plpgsql security definer set search_path='' as $$
#variable_conflict use_column
declare e uuid;s uuid;r jsonb;
begin
 select id into s from public.seasons where status='alpha' for update;e:=private.active_player_id();perform private.economy_process();
 select jsonb_build_object('server_now',now(),'next_tick',(select next_tick from private.military_clock where season_id=s),'treasury',(select treasury from public.empires where id=e),'debt',(select maintenance_debt from public.empires where id=e),
 'planets',coalesce((select jsonb_agg(to_jsonb(p)||jsonb_build_object('daily_recruits',private.recruitment_daily(p),'recruitment_cap',greatest(1,p.population/1000),'factory_price',private.factory_price(p.factories+1),'factory_hours',24*(1+.08*(p.factories-5))/(case when p.resource='ferros' then 1.15 else 1 end),'busy_factories',(select count(*) from private.ship_jobs where planet_id=p.id and kind<>'factory' and completed_at is null and cancelled_at is null))) from public.planets p where owner_empire_id=e),'[]'::jsonb),
 'fleets',coalesce((select jsonb_agg(to_jsonb(f)||jsonb_build_object('location',private.military_label(f.planet_id,e),'origin',private.military_label(f.origin_id,e),'destination',private.military_label(f.destination_id,e),'own_location',exists(select 1 from public.planets p where p.id=f.planet_id and owner_empire_id=e))) from private.fleets f where f.empire_id=e and status in ('stationed','transit')),'[]'::jsonb),
 'jobs',coalesce((select jsonb_agg(to_jsonb(j)||jsonb_build_object('planet',private.military_label(j.planet_id,e)) order by finishes_at) from private.ship_jobs j where empire_id=e and completed_at is null and cancelled_at is null),'[]'::jsonb),
 'reports',coalesce((select jsonb_agg(q order by occurred_at desc) from (select r.id,r.event,r.occurred_at,r.details,private.military_label(r.planet_id,e) planet from private.battle_reports r where empire_id=e order by occurred_at desc limit 100)q),'[]'::jsonb),
 'presence',coalesce((select jsonb_agg(to_jsonb(q)) from (select p.id,p.race||'_'||p.resource appearance,private.military_label(p.id,e) name,sum(f.ground_soldiers)::int soldiers,sum(f.soldiers)::int embarked,sum(f.scouts+f.bombers+f.fighters)::int ships,bool_or(f.mission='attack') attacking from private.fleets f join public.planets p on p.id=f.planet_id where f.empire_id=e and f.status='stationed' and p.owner_empire_id is distinct from e and f.scouts+f.bombers+f.fighters+f.soldiers+f.ground_soldiers>0 group by p.id)q),'[]'::jsonb)) into r;
 return r;
end $$;
create function public.military_command(p_action text,p_args jsonb,p_request_id uuid) returns jsonb language sql security invoker set search_path='' as $$select private.military_command(p_action,p_args,p_request_id);$$;
create function public.military_dashboard() returns jsonb language sql security invoker set search_path='' as $$select private.military_dashboard();$$;
revoke all on function private.recruitment_daily(public.planets),private.factory_price(integer),private.military_label(uuid,uuid),private.resolve_battle(uuid,timestamptz),private.military_process(timestamptz),private.economy_process_base(timestamptz),private.economy_process(timestamptz),private.military_command(text,jsonb,uuid),private.military_dashboard(),public.military_command(text,jsonb,uuid),public.military_dashboard() from public,anon,authenticated;
grant execute on function private.military_command(text,jsonb,uuid),private.military_dashboard(),public.military_command(text,jsonb,uuid),public.military_dashboard() to authenticated;
-- Keep the daily forecast consistent with owner-paid expedition upkeep.
alter function private.economy_overview() rename to economy_overview_planets;
create function private.economy_overview() returns jsonb language plpgsql security definer set search_path='' as $$
declare e uuid:=private.active_player_id();r jsonb;mil numeric;ships numeric;
begin
 r:=private.economy_overview_planets();
 select coalesce(sum((soldiers::numeric+ground_soldiers)*2),0),coalesce(sum(scouts::numeric*20+bombers::numeric*60+fighters::numeric*80),0) into mil,ships from private.fleets where empire_id=e and status in ('stationed','transit');
 if mil+ships>0 then r:=jsonb_set(r,'{planets}',(r->'planets')||jsonb_build_array(jsonb_build_object('id',null,'name','Forces expéditionnaires','civil',0,'trade',0,'trade_cost',0,'military',mil,'fleet',ships,'net',-mil-ships)));end if;return r;
end $$;
revoke all on function private.economy_overview_planets(),private.economy_overview() from public,anon,authenticated;
grant execute on function private.economy_overview() to authenticated;
