-- Sequential, prepaid assimilation queues; rank metrics are private and server-owned.
create table private.civilization_jobs(
 id uuid primary key default gen_random_uuid(),empire_id uuid not null references public.empires(id) on delete cascade,
 planet_id uuid not null references public.planets(id) on delete cascade,target_level integer not null check(target_level between 2 and 40),
 cost bigint not null check(cost>0),started_at timestamptz not null,finishes_at timestamptz not null,
 completed_at timestamptz,cancelled_at timestamptz,check(finishes_at=started_at+interval '72 hours')
);
create unique index civilization_one_open_level on private.civilization_jobs(planet_id,target_level) where completed_at is null and cancelled_at is null;
create index civilization_due on private.civilization_jobs(finishes_at) where completed_at is null and cancelled_at is null;
create index civilization_owner on private.civilization_jobs(empire_id,planet_id);
create table private.civilization_commands(empire_id uuid not null references public.empires(id) on delete cascade,request_id uuid not null,payload jsonb not null,result jsonb not null,primary key(empire_id,request_id));
create table private.player_merit(empire_id uuid primary key references public.empires(id) on delete cascade,
 produced_soldiers bigint not null default 0 check(produced_soldiers>=0),produced_scouts bigint not null default 0 check(produced_scouts>=0),
 produced_bombers bigint not null default 0 check(produced_bombers>=0),produced_fighters bigint not null default 0 check(produced_fighters>=0),
 destroyed_points numeric not null default 0 check(destroyed_points>=0));
alter table private.civilization_jobs enable row level security;
alter table private.civilization_commands enable row level security;
alter table private.player_merit enable row level security;
revoke all on private.civilization_jobs,private.civilization_commands,private.player_merit from public,anon,authenticated;
create function private.civilization_price(p_target integer) returns bigint language sql immutable strict set search_path='' as $$select case when p_target between 2 and 40 then round(80000*power((p_target-1)::numeric,.85))::bigint else null end;$$;
create function private.rank_catalog() returns jsonb language sql immutable set search_path='' as $$select '[
 {"name":"Cadet de Flotte","threshold":0,"tier":0},
 {"name":"Enseigne stellaire","threshold":300,"tier":1},
 {"name":"Lieutenant orbital","threshold":700,"tier":2},
 {"name":"Capitaine de corvette","threshold":1250,"tier":3},
 {"name":"Capitaine de frégate","threshold":1950,"tier":4},
 {"name":"Capitaine stellaire","threshold":2800,"tier":5},
 {"name":"Commandant d’escadre","threshold":3850,"tier":6},
 {"name":"Commodore","threshold":5100,"tier":7},
 {"name":"Contre-amiral","threshold":6550,"tier":8},
 {"name":"Amiral","threshold":8200,"tier":9},
 {"name":"Fleet Admiral","threshold":10000,"tier":10,"advanced_worlds":3,"combat_required":2000}
 ]'::jsonb;$$;
create function private.player_rank(p_empire uuid) returns jsonb language plpgsql stable set search_path='' as $$
declare civ bigint;advanced int;raw_production numeric;production numeric;combat numeric;total bigint;current_rank jsonb;next_rank jsonb;units jsonb;
begin
 select coalesce(sum(civilization),0)*100,count(*) filter(where civilization>=15) into civ,advanced from public.planets where owner_empire_id=p_empire;
 select .2*(produced_soldiers::numeric+4*produced_scouts::numeric+24*produced_bombers::numeric+32*produced_fighters::numeric),destroyed_points,
 jsonb_build_object('soldiers',produced_soldiers,'scouts',produced_scouts,'bombers',produced_bombers,'fighters',produced_fighters) into raw_production,combat,units from private.player_merit where empire_id=p_empire;
 raw_production:=coalesce(raw_production,0);combat:=coalesce(combat,0);production:=least(raw_production,civ*.4);total:=floor(civ+production+combat)::bigint;
 select x into current_rank from jsonb_array_elements(private.rank_catalog())x where (x->>'threshold')::bigint<=total and ((x->>'tier')::int<10 or (advanced>=3 and combat>=2000)) order by (x->>'tier')::int desc limit 1;
 select x into next_rank from jsonb_array_elements(private.rank_catalog())x where (x->>'tier')::int=(current_rank->>'tier')::int+1;
 return jsonb_build_object('name',current_rank->>'name','tier',(current_rank->>'tier')::int,'score',total,'civilization_points',civ,'production_points',floor(production),'raw_production_points',floor(raw_production),'combat_points',floor(combat),'advanced_worlds',advanced,'produced_units',coalesce(units,'{"soldiers":0,"scouts":0,"bombers":0,"fighters":0}'::jsonb),'next',next_rank,'catalog',private.rank_catalog());
end $$;
create function private.refresh_ranks(p_season uuid) returns void language sql set search_path='' as $$
 update public.empires e set grade=r.value->>'name' from (select id,private.player_rank(id) value from public.empires where season_id=p_season)r where e.id=r.id and e.grade is distinct from r.value->>'name';
$$;
-- Initial garrisons, captures and troop transfers are not production. Existing
-- delivered ship jobs have a verifiable origin and may be credited once here.
insert into private.player_merit(empire_id,produced_scouts,produced_bombers,produced_fighters)
select empire_id,count(*) filter(where kind='scout'),count(*) filter(where kind='bomber'),count(*) filter(where kind='fighter') from private.ship_jobs where completed_at is not null and cancelled_at is null group by empire_id;
create function private.credit_ship_production() returns trigger language plpgsql set search_path='' as $$
begin
 if old.completed_at is null and new.completed_at is not null and new.cancelled_at is null then
 insert into private.player_merit(empire_id,produced_scouts,produced_bombers,produced_fighters) values(new.empire_id,case when new.kind='scout' then 1 else 0 end,case when new.kind='bomber' then 1 else 0 end,case when new.kind='fighter' then 1 else 0 end)
 on conflict(empire_id) do update set produced_scouts=private.player_merit.produced_scouts+excluded.produced_scouts,produced_bombers=private.player_merit.produced_bombers+excluded.produced_bombers,produced_fighters=private.player_merit.produced_fighters+excluded.produced_fighters;
 end if;return new;
end $$;
create trigger ship_production_merit after update of completed_at on private.ship_jobs for each row execute function private.credit_ship_production();
create function private.cancel_captured_assimilation() returns trigger language plpgsql set search_path='' as $$
begin
 if old.owner_empire_id is distinct from new.owner_empire_id then update private.civilization_jobs set cancelled_at=now() where planet_id=new.id and completed_at is null and cancelled_at is null;end if;return new;
end $$;
create trigger civilization_capture after update of owner_empire_id on public.planets for each row execute function private.cancel_captured_assimilation();
create function private.credit_battle_losses(p_snapshot jsonb,p_victim uuid,p_side text,p_space_points numeric,p_ground_points numeric) returns void language plpgsql set search_path='' as $$
declare total_space numeric;total_ground numeric;v record;credit numeric;
begin
 select coalesce(sum((scouts+fighters*8)*(case when race='vael' then 1.15 when race='khar' then .85 else 1 end)),0),coalesce(sum(ground*.12*(case when race='khar' then 1.15 when race='vael' then .85 else 1 end)+bombers*2),0)
 into total_space,total_ground from jsonb_to_recordset(p_snapshot) as x(side text,race text,scouts int,bombers int,fighters int,ground int) where side<>p_side;
 for v in select empire_id,sum((scouts+fighters*8)*(case when race='vael' then 1.15 when race='khar' then .85 else 1 end)) space_power,sum(ground*.12*(case when race='khar' then 1.15 when race='vael' then .85 else 1 end)+bombers*2) ground_power
 from jsonb_to_recordset(p_snapshot) as x(empire_id uuid,side text,race text,scouts int,bombers int,fighters int,ground int)
 where side<>p_side and empire_id is not null and empire_id is distinct from p_victim
 and not exists(select 1 from private.clan_memberships a join private.clan_memberships b on a.clan_id=b.clan_id where a.empire_id=x.empire_id and b.empire_id=p_victim)
 group by empire_id loop
 credit:=coalesce(p_space_points*v.space_power/nullif(total_space,0),0)+coalesce(p_ground_points*v.ground_power/nullif(total_ground,0),0);
 if credit>0 then insert into private.player_merit(empire_id,destroyed_points) values(v.empire_id,credit) on conflict(empire_id) do update set destroyed_points=private.player_merit.destroyed_points+excluded.destroyed_points;end if;
 end loop;
end $$;

create or replace function private.resolve_battle(p_planet uuid,p_at timestamptz) returns void language plpgsql set search_path='' as $$
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
   perform private.credit_battle_losses(snap,u.empire_id,u.side,ls::numeric*4+lb::numeric*24+lf::numeric*32+(u.cargo-nc),lg);
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
 update private.military_clock set last_processed=v_limit,next_tick=c.next_tick where season_id=s.id;
 perform private.refresh_ranks(s.id);
 end loop;
end $$;
create function private.invest_civilization(p_planet_id uuid,p_quantity integer,p_expected_level integer,p_expected_tail integer,p_request_id uuid) returns jsonb language plpgsql security definer set search_path='' as $$
declare e uuid;s uuid;p public.planets%rowtype;tail int;start_at timestamptz;cost bigint;n int;prev private.civilization_commands%rowtype;payload jsonb;r jsonb;
begin
 select id into s from public.seasons where status='alpha' for update;e:=private.active_player_id();
 if p_request_id is null then raise exception 'Identifiant de commande requis.';end if;
 payload:=jsonb_build_object('planet',p_planet_id,'quantity',p_quantity,'level',p_expected_level,'tail',p_expected_tail);
 select * into prev from private.civilization_commands where empire_id=e and request_id=p_request_id;
 if found then if prev.payload<>payload then raise exception 'Identifiant déjà utilisé pour une autre commande.';end if;return prev.result;end if;
 perform private.economy_process();
 select * into p from public.planets where id=p_planet_id and owner_empire_id=e and season_id=s for update;
 if not found then raise exception 'Planète inaccessible.' using errcode='42501';end if;
 select greatest(p.civilization,coalesce(max(target_level),p.civilization)),greatest(now(),coalesce(max(finishes_at),now())) into tail,start_at from private.civilization_jobs where planet_id=p.id and completed_at is null and cancelled_at is null;
 if p_expected_level is null or p_expected_tail is null or p_expected_level<>p.civilization or p_expected_tail<>tail then raise exception 'Le devis de civilisation a changé. Actualisez avant de confirmer.';end if;
 if p_quantity is null or p_quantity<1 or p_quantity>40-tail then raise exception 'Investissement invalide : le niveau maximal est 40.';end if;
 select sum(private.civilization_price(levels.value)) into cost from generate_series(tail+1,tail+p_quantity) as levels(value);
 if exists(select 1 from public.empires where id=e and (treasury<cost or maintenance_debt>0)) then raise exception 'Trésorerie insuffisante ou entretien à régulariser.';end if;
 update public.empires set treasury=treasury-cost where id=e;
 for n in tail+1..tail+p_quantity loop
 insert into private.civilization_jobs(empire_id,planet_id,target_level,cost,started_at,finishes_at) values(e,p.id,n,private.civilization_price(n),start_at,start_at+interval '72 hours');start_at:=start_at+interval '72 hours';
 end loop;
 r:=jsonb_build_object('ok',true,'cost',cost,'last_level',tail+p_quantity,'finishes_at',start_at);
 insert into private.civilization_commands values(e,p_request_id,payload,r);return r;
end $$;
create function private.progression_dashboard() returns jsonb language plpgsql security definer set search_path='' as $$
declare e uuid;s uuid;r jsonb;
begin
 select id into s from public.seasons where status='alpha' for update;e:=private.active_player_id();perform private.economy_process();
 select jsonb_build_object('server_now',now(),'treasury',(select treasury from public.empires where id=e),'debt',(select maintenance_debt from public.empires where id=e),'rank',private.player_rank(e),
 'planets',coalesce((select jsonb_agg(jsonb_build_object('id',p.id,'name',p.name,'race',p.race,'resource',p.resource,'civilization',p.civilization,'population',p.population,
 'tail_level',greatest(p.civilization,coalesce((select max(target_level) from private.civilization_jobs where planet_id=p.id and completed_at is null and cancelled_at is null),p.civilization)),
 'jobs',coalesce((select jsonb_agg(jsonb_build_object('id',j.id,'target_level',j.target_level,'cost',j.cost,'started_at',j.started_at,'finishes_at',j.finishes_at) order by target_level) from private.civilization_jobs j where planet_id=p.id and completed_at is null and cancelled_at is null),'[]'::jsonb),
 'prices',(select jsonb_object_agg(n::text,private.civilization_price(n)) from generate_series(2,40)n)) order by p.created_at,p.serial) from public.planets p where owner_empire_id=e),'[]'::jsonb)) into r;
 return r;
end $$;
create function public.progression_dashboard() returns jsonb language sql security invoker set search_path='' as $$select private.progression_dashboard();$$;
create function public.invest_civilization(p_planet_id uuid,p_quantity integer,p_expected_level integer,p_expected_tail integer,p_request_id uuid) returns jsonb language sql security invoker set search_path='' as $$select private.invest_civilization(p_planet_id,p_quantity,p_expected_level,p_expected_tail,p_request_id);$$;
revoke all on function private.civilization_price(integer),private.rank_catalog(),private.player_rank(uuid),private.refresh_ranks(uuid),private.credit_ship_production(),private.cancel_captured_assimilation(),private.credit_battle_losses(jsonb,uuid,text,numeric,numeric),private.invest_civilization(uuid,integer,integer,integer,uuid),private.progression_dashboard(),public.progression_dashboard(),public.invest_civilization(uuid,integer,integer,integer,uuid) from public,anon,authenticated;
grant execute on function private.invest_civilization(uuid,integer,integer,integer,uuid),private.progression_dashboard(),public.progression_dashboard(),public.invest_civilization(uuid,integer,integer,integer,uuid) to authenticated;
select private.refresh_ranks(id) from public.seasons where status='alpha';
