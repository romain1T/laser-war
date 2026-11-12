select id from public.seasons where status='alpha' for update;select private.economy_process();
alter table public.planets add column ship_tech numeric not null default 0,add column army_tech numeric not null default 0,add column camouflaged boolean not null default false,add column destroyed_at timestamptz,add column fortification_cap numeric;
alter table private.fleets add column ship_tech numeric not null default 0,add column army_tech numeric not null default 0,add column massive_bombing boolean not null default false,add column gate_transit boolean not null default false;
create table private.gate_networks(id uuid primary key default gen_random_uuid(),season_id uuid not null references public.seasons(id),name text not null check(char_length(name) between 3 and 40),password_hash text not null,unique(season_id,name));
create table private.special_projects(planet_id uuid primary key references public.planets(id) on delete cascade,stasis boolean not null default false,gate_network uuid references private.gate_networks(id),gate_ready_at timestamptz,black_hole_ready_at timestamptz,black_hole_offensive boolean not null default false,doom_at timestamptz,last_at timestamptz not null default now(),population_damage numeric not null default 0,capacity_damage numeric not null default 0,factory_damage numeric not null default 0);
create table private.scan_jobs(id uuid primary key default gen_random_uuid(),empire_id uuid not null references public.empires(id) on delete cascade,origin_id uuid not null references public.planets(id) on delete cascade,target_id uuid not null references public.planets(id) on delete cascade,kind text not null check(kind in('stasis','fleets','armies','trade')),mode text not null check(mode in('basic','anonymous','stealth')),effective_mode text not null,created_at timestamptz not null,finishes_at timestamptz not null,completed_at timestamptz,result jsonb);
create index scan_next_completion on private.scan_jobs(finishes_at) where completed_at is null;
alter table private.gate_networks enable row level security;alter table private.special_projects enable row level security;alter table private.scan_jobs enable row level security;
revoke all on private.gate_networks,private.special_projects,private.scan_jobs from public,anon,authenticated;
create function private.reserve_technology() returns trigger language plpgsql set search_path='' as $$
#variable_conflict use_column

declare os bigint;ns bigint;source numeric;begin
 if new.owner_empire_id is distinct from old.owner_empire_id then return new;end if;
 os:=old.scouts::bigint+old.bombers+old.fighters;ns:=new.scouts::bigint+new.bombers+new.fighters;
 if ns>os then source:=coalesce(nullif(current_setting('lw.ship_source_level',true),'')::numeric,private.tech_level(new.owner_empire_id,'ships_'||new.race));new.ship_tech:=(old.ship_tech*os+source*(ns-os))/ns;end if;
 if new.soldiers>old.soldiers then source:=coalesce(nullif(current_setting('lw.army_source_level',true),'')::numeric,private.tech_level(new.owner_empire_id,'armies_'||new.race));new.army_tech:=(old.army_tech*old.soldiers+source*(new.soldiers-old.soldiers))/new.soldiers;end if;
 return new;end $$;
create trigger reserve_technology before update of scouts,bombers,fighters,soldiers on public.planets for each row execute function private.reserve_technology();
create function private.fleet_technology_origin() returns trigger language plpgsql set search_path='' as $$
#variable_conflict use_column
declare p public.planets%rowtype;begin
 select * into p from public.planets where id=new.origin_id;
 new.camouflaged:=new.camouflaged or coalesce(p.camouflaged,false);new.ship_tech:=coalesce(nullif(current_setting('lw.ship_source_level',true),'')::numeric,p.ship_tech,0);new.army_tech:=coalesce(nullif(current_setting('lw.army_source_level',true),'')::numeric,p.army_tech,0);return new;end $$;
create trigger fleet_technology_origin before insert on private.fleets for each row execute function private.fleet_technology_origin();
-- All transfers use the source units' weighted research level, never today's research.
do $patch$ declare src text;begin
 select pg_get_functiondef('private.military_command(text,jsonb,uuid)'::regprocedure) into src;
 src:=replace(src,$text$elsif p_action='disband' then$text$,$text$elsif p_action='disband' then perform set_config('lw.ship_source_level',f.ship_tech::text,true);perform set_config('lw.army_source_level',f.army_tech::text,true);$text$);
 src:=replace(src,'elsif delta<0 then','elsif delta<0 then perform set_config(''lw.army_source_level'',f.army_tech::text,true);');
 src:=replace(src,'if f.ground_soldiers>0 then insert','if f.ground_soldiers>0 then perform set_config(''lw.army_source_level'',f.army_tech::text,true);insert');
 src:=replace(src,'if delta>0 then','if delta>0 then perform set_config(''lw.loaded_army_points'',''0'',true);');
 src:=replace(src,'remaining:=remaining-take_n;end if;','perform set_config(''lw.loaded_army_points'',(current_setting(''lw.loaded_army_points'')::numeric+p.army_tech*take_n)::text,true);remaining:=remaining-take_n;end if;');
 src:=replace(src,'remaining:=remaining-take_n;exit when remaining=0;','perform set_config(''lw.loaded_army_points'',(current_setting(''lw.loaded_army_points'')::numeric+g.army_tech*take_n)::text,true);remaining:=remaining-take_n;exit when remaining=0;');
 src:=replace(src,'update private.fleets set soldiers=q where id=f.id;','update private.fleets set soldiers=q,army_tech=case when delta>0 then (f.army_tech*(f.soldiers+f.ground_soldiers)+current_setting(''lw.loaded_army_points'')::numeric)/greatest(1,q+f.ground_soldiers) else army_tech end where id=f.id;');
 src:=replace(src,'return r;','perform set_config(''lw.ship_source_level'','''',true);perform set_config(''lw.army_source_level'','''',true);return r;');execute src;
 select pg_get_functiondef('private.technology_command_base(text,jsonb,uuid)'::regprocedure) into src;
 src:=replace(src,'if v_take>0 then','if v_take>0 then perform set_config(''lw.army_source_level'',v_p.army_tech::text,true);');
 src:=replace(src,'for v_group in select','for v_group in select');
 src:=replace(src,'v_take:=least(v_group.ground_soldiers,v_remaining);','v_take:=least(v_group.ground_soldiers,v_remaining);perform set_config(''lw.army_source_level'',v_group.army_tech::text,true);');
 src:=replace(src,'return v_result;','perform set_config(''lw.army_source_level'','''',true);return v_result;');execute src;
end $patch$;
create function private.set_stasis(pid uuid,enabled boolean,t timestamptz) returns void language plpgsql set search_path='' as $$
#variable_conflict use_column
declare old_enabled boolean;factor numeric;begin
 insert into private.special_projects(planet_id) values(pid) on conflict do nothing;
 select stasis into old_enabled from private.special_projects where planet_id=pid for update;if old_enabled=enabled then return;end if;
 factor:=case when enabled then 3 else 1.0/3 end;
 update private.ship_jobs set finishes_at=t+(finishes_at-t)*factor::double precision,started_at=t-(t-started_at)*factor::double precision where planet_id=pid and kind<>'factory' and completed_at is null and cancelled_at is null and paused_at is null;
 update private.special_projects set stasis=enabled where planet_id=pid;
end $$;
create function private.stasis_job_duration() returns trigger language plpgsql set search_path='' as $$
#variable_conflict use_column
begin
 if new.kind<>'factory' and exists(select 1 from private.special_projects where planet_id=new.planet_id and stasis) then new.finishes_at:=new.started_at+(new.finishes_at-new.started_at)*3;end if;return new;end $$;
create trigger stasis_job_duration before insert on private.ship_jobs for each row execute function private.stasis_job_duration();
create function private.advanced_next_event(s uuid) returns timestamptz language sql stable set search_path='' as $$select least((select min(j.finishes_at) from private.scan_jobs j join public.planets p on p.id=j.origin_id where p.season_id=s and j.completed_at is null),(select min(z.doom_at) from private.special_projects z join public.planets p on p.id=z.planet_id where p.season_id=s and p.destroyed_at is null),(select min(z.purifying_until) from private.planet_security z join public.planets p on p.id=z.planet_id where p.season_id=s))$$;
alter table private.special_projects add column energy_fraction numeric not null default 0;
alter table private.fleets add column launched_at timestamptz;
create function private.track_fleet_departure() returns trigger language plpgsql set search_path='' as $$
#variable_conflict use_column
begin if new.status='transit' and old.status<>'transit' then new.launched_at:=new.departed_at;end if;return new;end $$;
create trigger track_fleet_departure before update of status on private.fleets for each row execute function private.track_fleet_departure();
create table private.black_hole_targets(origin_id uuid not null references public.planets(id) on delete cascade,target_id uuid not null references public.planets(id) on delete cascade,delay_seconds int not null,primary key(origin_id,target_id));
alter table private.black_hole_targets enable row level security;revoke all on private.black_hole_targets from public,anon,authenticated;
create function private.disconnect_gate(pid uuid,t timestamptz) returns void language plpgsql set search_path='' as $$
#variable_conflict use_column
declare f record;dest uuid;begin
 update private.special_projects set gate_network=null,gate_ready_at=null where planet_id=pid;
 for f in select * from private.fleets where destination_id=pid and status='transit' and gate_transit loop
 select id into dest from public.planets where season_id=f.season_id and destroyed_at is null and id<>pid order by random() limit 1;
 if dest is null then update private.fleets set status='destroyed',scouts=0,bombers=0,fighters=0,soldiers=0,ground_soldiers=0 where id=f.id;
 else update private.fleets set destination_id=dest where id=f.id;end if;
 end loop;
end $$;
create function private.annihilate_planet(pid uuid,t timestamptz,offensive boolean default false) returns void language plpgsql set search_path='' as $$
#variable_conflict use_column

declare p public.planets%rowtype;d record;begin
 select * into p from public.planets where id=pid and destroyed_at is null for update;if not found then return;end if;
 perform private.disconnect_gate(pid,t);
 if offensive then
 for d in select * from private.black_hole_targets where origin_id=pid loop
 insert into private.special_projects(planet_id,doom_at) values(d.target_id,t+make_interval(secs=>d.delay_seconds)) on conflict(planet_id) do update set doom_at=least(private.special_projects.doom_at,excluded.doom_at);
 end loop;end if;
 update private.ship_jobs set cancelled_at=t where planet_id=pid and completed_at is null and cancelled_at is null;
 update private.civilization_jobs set cancelled_at=t where planet_id=pid and completed_at is null and cancelled_at is null;
 update private.research_jobs set cancelled_at=t where planet_id=pid and completed_at is null and cancelled_at is null;
 delete from private.infiltrations where target_id=pid or origin_id=pid;
 perform set_config('lw.destroy_damage','on',true);
 update private.trade_links set status='cancelled',closed_at=t where pid in(planet_a,planet_b) and status in('active','pending');
 update public.planets set owner_empire_id=null,destroyed_at=t,population=0,scouts=0,bombers=0,fighters=0,soldiers=0,energy=0,trade_capacity=0,factories=0 where id=pid;
 update private.fleets set status='destroyed',scouts=0,bombers=0,fighters=0,soldiers=0,ground_soldiers=0 where (planet_id=pid and status='stationed') or (origin_id=pid and status='transit' and launched_at>t-interval '2 hours' and not gate_transit);
 update private.special_projects set stasis=false,black_hole_ready_at=null,gate_network=null,gate_ready_at=null,doom_at=null where planet_id=pid;
 perform set_config('lw.destroy_damage','',true);
end $$;
create function private.scan_result(j private.scan_jobs) returns jsonb language plpgsql set search_path='' as $$
#variable_conflict use_column
declare p public.planets%rowtype;v numeric;begin
 select * into p from public.planets where id=j.target_id;
 if p.destroyed_at is not null then return jsonb_build_object('destroyed',true);end if;
 if j.kind='stasis' then return jsonb_build_object('stasis',exists(select 1 from private.special_projects where planet_id=p.id and stasis));
 elsif j.kind='fleets' then
 select (p.scouts+p.fighters*8)+coalesce(sum(scouts+fighters*8),0) into v from private.fleets where planet_id=p.id and status='stationed';return jsonb_build_object('approximate_space_power',round(v*(.9+random()*.2)),'margin_percent',10);
 elsif j.kind='armies' then
 select p.soldiers+coalesce(sum(ground_soldiers),0) into v from private.fleets where planet_id=p.id and status='stationed';return jsonb_build_object('approximate_ground_power',round(v*(.9+random()*.2)),'margin_percent',10);
 else return jsonb_build_object('trade_links',coalesce((select jsonb_agg(x) from(select private.military_label(case when l.planet_a=p.id then l.planet_b else l.planet_a end,j.empire_id) planet,l.quantity from private.trade_links l where p.id in(l.planet_a,l.planet_b) and l.status='active' order by l.quantity desc,l.id limit 5)x),'[]'::jsonb));end if;
end $$;
create function private.advance_special_projects(s uuid,t timestamptz) returns void language plpgsql set search_path='' as $$
#variable_conflict use_column

declare z private.special_projects%rowtype;p public.planets%rowtype;j private.scan_jobs%rowtype;hours numeric;usage numeric;units int;d record;result_data jsonb;
begin
 for j in select j.* from private.scan_jobs j join public.planets p on p.id=j.origin_id where p.season_id=s and j.completed_at is null and j.finishes_at<=t for update of j loop
 result_data:=private.scan_result(j);update private.scan_jobs set completed_at=t,result=result_data where id=j.id;
 insert into private.battle_reports(empire_id,planet_id,occurred_at,event,details) values(j.empire_id,j.target_id,t,'scan_report',jsonb_build_object('scan_id',j.id,'kind',j.kind,'result',result_data));end loop;
 for z in select z.* from private.special_projects z join public.planets p on p.id=z.planet_id where p.season_id=s and p.destroyed_at is null and z.last_at<t order by z.planet_id for update of z loop
 select * into p from public.planets where id=z.planet_id for update;
 if z.doom_at<=t then perform private.annihilate_planet(p.id,t,false);continue;end if;
 hours:=greatest(0,extract(epoch from(t-z.last_at))/3600);
 usage:=z.energy_fraction+hours*((case when z.stasis then 1+case when private.ground_superiority(p.id,t) and private.planet_at_war(p.id) then 1 else 0 end else 0 end)+(case when z.gate_network is not null then 1 else 0 end)+(case when z.black_hole_ready_at is not null then 1 else 0 end));units:=floor(usage)::int;
 if units>p.energy then
 perform private.set_stasis(p.id,false,t);perform private.disconnect_gate(p.id,t);
 update private.special_projects set black_hole_ready_at=null,energy_fraction=0,last_at=t where planet_id=p.id;update public.planets set energy=0 where id=p.id;
 else update public.planets set energy=energy-units where id=p.id;update private.special_projects set energy_fraction=usage-units,last_at=t where planet_id=p.id;end if;
 end loop;
end $$;
alter table public.planets drop constraint planets_factories_check;
alter table public.planets add constraint planets_factories_check check(factories between 0 and 200);
create function private.special_command(p_action text,p_args jsonb,p_request_id uuid) returns jsonb language plpgsql security definer set search_path='' as $$
#variable_conflict use_column

declare e uuid;s uuid;p public.planets%rowtype;target public.planets%rowtype;f private.fleets%rowtype;z private.special_projects%rowtype;prev private.technology_commands%rowtype;payload jsonb;r jsonb;secret text:=coalesce(p_args->>'password','');secret_hash text;enabled boolean;network private.gate_networks%rowtype;n int;energy_cost int;mode text;effective text;j uuid;ap numeric;dp numeric;d record;t timestamptz:=now();
begin
 select id into s from public.seasons where status='alpha' for update;e:=private.active_player_id();if p_request_id is null or octet_length(secret)>72 then raise exception 'Commande invalide.';end if;
 payload:=jsonb_build_object('action','special:'||p_action,'args',p_args-'password');select * into prev from private.technology_commands where empire_id=e and request_id=p_request_id;
 if found then if prev.payload<>payload or(prev.secret_hash is not null and extensions.crypt(secret,prev.secret_hash)<>prev.secret_hash) or(prev.secret_hash is null and secret<>'') then raise exception 'Identifiant déjà utilisé.';end if;return prev.result;end if;
 perform private.economy_process();
 if p_action in('camouflage','massive_bombing','gate_jump') and p_args->>'fleet_id' is not null then
 select * into f from private.fleets where id=(p_args->>'fleet_id')::uuid and empire_id=e and status='stationed' for update;if not found then raise exception 'Flotte stationnée requise.';end if;
 select * into p from public.planets where id=f.planet_id and destroyed_at is null for update;
 else select * into p from public.planets where id=(p_args->>'planet_id')::uuid and owner_empire_id=e and destroyed_at is null for update;end if;
 if p.id is null then raise exception 'Planète inaccessible.';end if;
 insert into private.special_projects(planet_id) values(p.id) on conflict do nothing;select * into z from private.special_projects where planet_id=p.id for update;
 if p_action='camouflage' then
 if private.tech_level(e,'camouflage')=0 then raise exception 'Recherchez le bouclier entropique.';end if;enabled:=(p_args->>'enabled')::boolean;if enabled is null then raise exception 'Choix requis.';end if;
 if f.id is not null then
 if f.camouflaged<>enabled then update private.fleets set camouflaged=enabled,unavailable_until=case when unavailable_until>t then unavailable_until else t+interval '1 hour' end,ground_ready_at=case when ground_ready_at>t then ground_ready_at else t+interval '1 hour' end where id=f.id;end if;
 else if p.camouflaged<>enabled then update public.planets set camouflaged=enabled,garrison_ready_at=case when garrison_ready_at>t then garrison_ready_at else t+interval '1 hour' end where id=p.id;end if;end if;
 elsif p_action='massive_bombing' then
 if private.tech_level(e,'massive_bombing')=0 or f.id is null or f.bombers=0 then raise exception 'Bombardiers et technologie requis.';end if;enabled:=(p_args->>'enabled')::boolean;if enabled is null then raise exception 'Choix requis.';end if;
 update private.fleets set massive_bombing=enabled where id=f.id;
 elsif p_action='stasis' then
 if private.tech_level(e,'stasis')=0 then raise exception 'Recherchez les tranchées stellaires.';end if;enabled:=(p_args->>'enabled')::boolean;if enabled is null then raise exception 'Choix requis.';end if;
 if enabled and not z.stasis then
 if p.captured_at>t-interval '24 hours' then raise exception 'Attendez 24 heures après la prise de contrôle.';end if;
 select coalesce(sum(scouts+fighters*8) filter(where mission='attack'),0),coalesce(sum(scouts+fighters*8) filter(where mission='defend'),0)+p.scouts+p.fighters*8 into ap,dp from private.fleets where planet_id=p.id and status='stationed';
 if ap>0 and ap>=dp*1.01 then raise exception 'La supériorité spatiale ennemie empêche le déploiement.';end if;
 if p.energy<2 then raise exception 'Deux charges d’énergie requises.';end if;update public.planets set energy=energy-2 where id=p.id;end if;
 perform private.set_stasis(p.id,enabled,t);
 elsif p_action='scan' then
 if private.tech_level(e,'scan_'||(p_args->>'kind'))=0 then raise exception 'Technologie de scan requise.';end if;
 select * into target from public.planets where id=(p_args->>'target_id')::uuid and destroyed_at is null and season_id=s;
 if not found or not target.id=any(array(select q.id from public.planets q where q.season_id=s and q.id<>p.id and q.destroyed_at is null order by power(q.x-p.x,2)+power(q.y-p.y,2),q.id limit 30)) then raise exception 'Choisissez une des trente planètes les plus proches.';end if;
 mode:=p_args->>'mode';energy_cost:=case mode when 'basic' then 1 when 'anonymous' then 2 when 'stealth' then 4 end;
 if energy_cost is null or p.energy<energy_cost or exists(select 1 from public.empires where id=e and(treasury<80000 or maintenance_debt>0)) then raise exception 'Énergie ou trésorerie insuffisante.';end if;
 effective:=case when mode='anonymous' and random()<.05 then 'basic' when mode='stealth' and random()<.05 then 'anonymous' else mode end;
 update public.planets set energy=energy-energy_cost where id=p.id;update public.empires set treasury=treasury-80000 where id=e;
 insert into private.scan_jobs(empire_id,origin_id,target_id,kind,mode,effective_mode,created_at,finishes_at) values(e,p.id,target.id,p_args->>'kind',mode,effective,t,t+interval '4 hours') returning id into j;
 if effective<>'stealth' and target.owner_empire_id is not null then insert into private.battle_reports(empire_id,planet_id,occurred_at,event,details) values(target.owner_empire_id,target.id,t,'scan_warning',jsonb_build_object('origin',case when effective='basic' then private.military_label(p.id,target.owner_empire_id) else 'Origine inconnue' end));end if;
 elsif p_action='gate_connect' then
 if private.tech_level(e,'stargate')=0 then raise exception 'Recherchez la porte stellaire massive.';end if;
 if z.gate_network is not null then raise exception 'Déconnectez d’abord cette porte.';end if;
 if char_length(btrim(p_args->>'network')) not between 3 and 40 or octet_length(secret)<8 then raise exception 'Nom de réseau et code de huit caractères requis.';end if;
 select * into network from private.gate_networks where season_id=s and name=btrim(p_args->>'network') for update;
 if found then if extensions.crypt(secret,network.password_hash)<>network.password_hash then raise exception 'Connexion au réseau refusée.';end if;
 else insert into private.gate_networks(season_id,name,password_hash) values(s,btrim(p_args->>'network'),extensions.crypt(secret,extensions.gen_salt('bf',10))) returning * into network;end if;
 select count(*) into n from private.special_projects where gate_network=network.id;
 update private.special_projects set gate_network=network.id,gate_ready_at=t+make_interval(hours=>24+6*n),last_at=t where planet_id=p.id;
 elsif p_action='gate_disconnect' then perform private.disconnect_gate(p.id,t);
 elsif p_action='gate_jump' then
 if f.id is null or f.unavailable_until>t or f.ground_ready_at>t or f.scouts+f.bombers+f.fighters=0 then raise exception 'Flotte indisponible pour le saut.';end if;
 select * into target from public.planets where id=(p_args->>'target_id')::uuid and destroyed_at is null and season_id=s;
 if z.gate_network is null or z.gate_ready_at>t or target.id=p.id or not exists(select 1 from private.special_projects q where q.planet_id=target.id and q.gate_network=z.gate_network and q.gate_ready_at<=t) then raise exception 'Porte non connectée au même réseau.';end if;
 mode:=p_args->>'mission';if mode is null or mode not in('attack','defend') or(target.owner_empire_id=e and mode='attack') then raise exception 'Mission invalide.';end if;
 if f.ground_soldiers>0 then perform set_config('lw.army_source_level',f.army_tech::text,true);insert into private.fleets(empire_id,season_id,name,race,supply_planet,planet_id,origin_id,mission,ground_soldiers,camouflaged) values(e,s,left(f.name||' · garnison',40),f.race,f.supply_planet,p.id,p.id,f.mission,f.ground_soldiers,f.camouflaged);perform set_config('lw.army_source_level','',true);end if;
 update private.fleets set origin_id=p.id,route_x=p.x,route_y=p.y,planet_id=null,destination_id=target.id,departed_at=t,arrives_at=t+interval '10 hours',lands_at=null,ground_soldiers=0,status='transit',gate_transit=true,mission=mode where id=f.id;
 elsif p_action='black_hole_prepare' then
 enabled:=coalesce((p_args->>'offensive')::boolean,false);
 if p.governance<>'tyrannie' or private.tech_level(e,case when enabled then 'black_hole_offensive' else 'black_hole_4' end)=0 then raise exception 'Tyrannie et recherches de confinement requises.';end if;
 if z.black_hole_ready_at is not null then raise exception 'Un confinement existe déjà.';end if;
 update private.special_projects set black_hole_ready_at=t+case when enabled then interval '96 hours' else interval '48 hours' end,black_hole_offensive=enabled,last_at=t where planet_id=p.id;
 if enabled then
 delete from private.black_hole_targets where origin_id=p.id;
 insert into private.black_hole_targets select p.id,q.id,(86400*(16+15*q.distance/greatest(1,max(q.distance)over())))::int from(select x.id,sqrt(power(x.x-p.x,2)+power(x.y-p.y,2)) distance from public.planets x where x.season_id=s and x.id<>p.id and x.destroyed_at is null order by distance,x.id limit(select count(*)::int/8 from public.planets where season_id=s and destroyed_at is null and id<>p.id))q;
 insert into private.battle_reports(empire_id,planet_id,occurred_at,event,details) select distinct q.owner_empire_id,q.id,t,'black_hole_warning',jsonb_build_object('origin',private.military_label(p.id,q.owner_empire_id),'ready_at',t+interval '96 hours') from private.black_hole_targets d join public.planets q on q.id=d.target_id where d.origin_id=p.id and q.owner_empire_id is not null;
 end if;
 elsif p_action='black_hole_cancel' then update private.special_projects set black_hole_ready_at=null where planet_id=p.id;delete from private.black_hole_targets where origin_id=p.id;
 elsif p_action='black_hole_activate' then
 if p.governance<>'tyrannie' or z.black_hole_ready_at is null or z.black_hole_ready_at>t then raise exception 'Confinement non prêt ou régime incompatible.';end if;
 perform private.annihilate_planet(p.id,t,z.black_hole_offensive);
 elsif p_action='energy_blast' then
 n:=(p_args->>'energy')::int;if n is null or n<1 or n>p.energy or private.tech_level(e,'energy_blast')=0 then raise exception 'Onde indisponible ou quantité d’énergie invalide.';end if;
 update public.planets set energy=energy-n where id=p.id;
 for target in select * from public.planets where season_id=s and id<>p.id and destroyed_at is null and sqrt(power(x-p.x,2)+power(y-p.y,2))<=n*11.25 loop
 update public.planets set energy=0,energy_fraction=0,fortification_cap=least(private.fortification(target,t),.13) where id=target.id;
 update private.special_projects set black_hole_ready_at=null where planet_id=target.id and black_hole_ready_at<=t;
 if target.owner_empire_id is not null then insert into private.battle_reports(empire_id,planet_id,occurred_at,event,details) values(target.owner_empire_id,target.id,t,'energy_blast',jsonb_build_object('origin',private.military_label(p.id,target.owner_empire_id)));end if;
 end loop;
 else raise exception 'Action inconnue.';end if;
 r:=jsonb_build_object('ok',true,'id',coalesce(j,f.id,p.id));if secret<>'' then secret_hash:=extensions.crypt(secret,extensions.gen_salt('bf',10));end if;
 insert into private.technology_commands(empire_id,request_id,payload,result,secret_hash) values(e,p_request_id,payload,r,secret_hash);return r;
end $$;
create function public.special_command(p_action text,p_args jsonb,p_request_id uuid) returns jsonb language sql security invoker set search_path='' as $$select private.special_command(p_action,p_args,p_request_id)$$;
revoke all on function public.special_command(text,jsonb,uuid),private.special_command(text,jsonb,uuid) from public,anon;grant execute on function public.special_command(text,jsonb,uuid),private.special_command(text,jsonb,uuid) to authenticated;
create function private.damage_exploitations(pid uuid,n int,t timestamptz) returns void language plpgsql set search_path='' as $$
#variable_conflict use_column
declare cap int;excess int;l private.trade_links%rowtype;
begin
 if n<=0 then return;end if;
 perform set_config('lw.destroy_damage','on',true);
 update public.planets set trade_capacity=greatest(0,trade_capacity-n) where id=pid returning trade_capacity into cap;
 excess:=greatest(0,private.trade_used(pid)-cap);
 for l in select * from private.trade_links where pid in(planet_a,planet_b) and status in('active','pending') order by created_at desc,id for update loop
 exit when excess=0;
 if l.quantity<=excess then update private.trade_links set status='cancelled',closed_at=t where id=l.id;excess:=excess-l.quantity;
 else update private.trade_links set quantity=quantity-excess where id=l.id;excess:=0;end if;
 end loop;
 perform set_config('lw.destroy_damage','',true);
end $$;
create function private.massive_bombardment(pid uuid,t timestamptz,snapshot jsonb,slow numeric) returns void language plpgsql set search_path='' as $$
#variable_conflict use_column
declare p public.planets%rowtype;z private.special_projects%rowtype;b numeric;poploss numeric;caploss numeric;facloss numeric;n int;j record;
begin
 select coalesce(sum(bombers*(case when camouflaged then .75 else 1 end)),0)/slow into b from jsonb_to_recordset(snapshot)x(side text,bombers int,camouflaged boolean,massive_bombing boolean) where side='attack' and massive_bombing;
 if b=0 then return;end if;
 select * into p from public.planets where id=pid;
 insert into private.special_projects(planet_id) values(pid) on conflict do nothing;select * into z from private.special_projects where planet_id=pid for update;
 poploss:=z.population_damage+b*50;caploss:=z.capacity_damage+b*.02;facloss:=z.factory_damage+b*.01;
 perform set_config('lw.destroy_damage','on',true);
 update public.planets set population=greatest(0,population-floor(poploss)::bigint),factories=greatest(0,factories-floor(facloss)::int) where id=pid returning factories into n;
 perform private.damage_exploitations(pid,floor(caploss)::int,t);
 -- Destroyed production lines lose their unfinished work, without a refund.
 for j in select id from private.ship_jobs where planet_id=pid and kind<>'factory' and completed_at is null and cancelled_at is null order by started_at desc,id offset n loop update private.ship_jobs set cancelled_at=t where id=j.id;end loop;
 update private.special_projects set population_damage=poploss-floor(poploss),capacity_damage=caploss-floor(caploss),factory_damage=facloss-floor(facloss) where planet_id=pid;
 perform set_config('lw.destroy_damage','',true);
end $$;
create function private.combat_opponents(snapshot jsonb,pid uuid,my_side text) returns jsonb language sql stable set search_path='' as $$
 select coalesce(jsonb_agg(jsonb_build_object('race',q.race,'name',case when q.hidden then 'Forces camouflées' else u.username end)), '[]'::jsonb)
 from(select distinct x.empire_id,x.race,(x.camouflaged or exists(select 1 from public.planets p where p.id=pid and p.owner_empire_id=x.empire_id and p.anonymous_until>now())) hidden from jsonb_to_recordset(snapshot)x(empire_id uuid,race text,side text,camouflaged boolean) where side<>my_side)q left join public.empires e on e.id=q.empire_id left join public.profiles u on u.id=e.player_id;
$$;
do $patch$ declare src text;begin
 select pg_get_functiondef('private.resolve_battle(uuid,timestamptz)'::regprocedure) into src;
 src:=replace(src,'fort numeric;','fort numeric;slow numeric;ast numeric;dst numeric;agt numeric;dgt numeric;');
 src:=replace(src,'end ready','end ready,p.ship_tech,p.army_tech,p.camouflaged,false massive_bombing');
 src:=replace(src,'end from private.fleets f where f.planet_id=p.id','end,f.ship_tech,f.army_tech,f.camouflaged,f.massive_bombing from private.fleets f where f.planet_id=p.id');
 src:=replace(src,'ground int,ready int)','ground int,ready int,camouflaged boolean)');
 src:=replace(src,$text$when race='khar' then .85 else 1 end))::numeric power$text$,$text$when race='khar' then .85 else 1 end)*(case when camouflaged then .75 else 1 end))::numeric power$text$);
 src:=replace(src,$text$when race='vael' then .85 else 1 end))::numeric ground_power$text$,$text$when race='vael' then .85 else 1 end)*(case when camouflaged then .75 else 1 end))::numeric ground_power$text$);
 src:=replace(src,'sum(bombers)::numeric bombers','sum(bombers*(case when camouflaged then .75 else 1 end))::numeric bombers');
 src:=replace(src,' def.ground_power:=', $buff$
 select coalesce(sum(ship_tech*(scouts+bombers+fighters)) filter(where side='attack')/greatest(1,sum(scouts+bombers+fighters) filter(where side='attack')),0),coalesce(sum(ship_tech*(scouts+bombers+fighters)) filter(where side='defend')/greatest(1,sum(scouts+bombers+fighters) filter(where side='defend')),0),coalesce(sum(army_tech*ready) filter(where side='attack')/greatest(1,sum(ready) filter(where side='attack')),0),coalesce(sum(army_tech*ready) filter(where side='defend')/greatest(1,sum(ready) filter(where side='defend')),0) into ast,dst,agt,dgt from jsonb_to_recordset(snap)x(side text,ship_tech numeric,army_tech numeric,scouts int,bombers int,fighters int,ready int);
 att.power:=coalesce(att.power,0)*(1+least(.3,greatest(0,ast-dst)*.03));def.power:=coalesce(def.power,0)*(1+least(.3,greatest(0,dst-ast)*.03));
 att.ground_power:=coalesce(att.ground_power,0)*(1+least(.3,greatest(0,agt-dgt)*.03));def.ground_power:=coalesce(def.ground_power,0)*(1+least(.3,greatest(0,dgt-agt)*.03));
 slow:=case when exists(select 1 from private.special_projects where planet_id=p.id and stasis) then 3 else 1 end;
 if att.power>=3*def.power then perform private.massive_bombardment(p.id,p_at,snap,slow);end if;
 def.ground_power:=$buff$);
 src:=replace(src,'cargo int,local boolean)','cargo int,local boolean,massive_bombing boolean)');
 src:=replace(src,'   insert into private.battle_damage','   if u.massive_bombing then sr:=least(1,sr*2);end if;sr:=sr/slow;gr:=gr/slow;
   insert into private.battle_damage');
 src:=replace(src,$text$jsonb_build_object('sides',sides$text$, $text$jsonb_build_object('opponents',private.combat_opponents(snap,p.id,t.side),'sides',sides$text$);execute src;
end $patch$;
alter table public.planets add column fortification_blast_at timestamptz;
alter table public.planets drop constraint neutral_trade_capacity_fixed;
alter table public.planets add constraint neutral_trade_capacity_fixed check(owner_empire_id is not null or trade_capacity<=5);
alter function private.fortification(public.planets,timestamptz) rename to fortification_before_blast;
create function private.fortification(p public.planets,t timestamptz) returns numeric language sql immutable set search_path='' as $$select case when p.fortification_cap is null then private.fortification_before_blast(p,t) else least(private.fortification_before_blast(p,t),p.fortification_cap+private.fortification_before_blast(jsonb_populate_record(p,jsonb_build_object('captured_at',p.fortification_blast_at)),t)) end$$;
alter function private.galaxy_signals() rename to galaxy_signals_before_destruction;
create function private.galaxy_signals() returns table(id uuid,designation text,x double precision,y double precision,clan_name text,is_own boolean) language sql stable security definer set search_path='' as $$select q.* from private.galaxy_signals_before_destruction()q join public.planets p on p.id=q.id where p.destroyed_at is null$$;
revoke all on function private.galaxy_signals_before_destruction(),private.galaxy_signals() from public,anon,authenticated;
do $patch$ declare src text;begin
 select pg_get_functiondef('private.neutral_world_rules()'::regprocedure) into src;src:=replace(src,'begin','begin if current_setting(''lw.destroy_damage'',true)=''on'' or new.destroyed_at is not null then return new;end if;');execute src;
 select pg_get_functiondef('private.guard_trade_siege()'::regprocedure) into src;src:=replace(src,'begin','begin if current_setting(''lw.destroy_damage'',true)=''on'' then return new;end if;');execute src;
 select pg_get_functiondef('private.capture_military_state()'::regprocedure) into src;src:=replace(src,'new.captured_at:=','new.fortification_cap:=case when current_setting(''lw.capture_kind'',true)=''infiltration'' then old.fortification_cap else null end;new.fortification_blast_at:=case when current_setting(''lw.capture_kind'',true)=''infiltration'' then old.fortification_blast_at else null end;new.captured_at:=');execute src;
 select pg_get_functiondef('private.infiltration_allowed(uuid,uuid,uuid)'::regprocedure) into src;src:=replace(src,'q.id=t where','q.id=t and q.destroyed_at is null where');execute src;
 select pg_get_functiondef('private.special_command(text,jsonb,uuid)'::regprocedure) into src;src:=replace(src,'fortification_cap=least(private.fortification(target,t),.13)','fortification_cap=least(private.fortification(target,t),.13),fortification_blast_at=t');execute src;
 select pg_get_functiondef('private.military_command(text,jsonb,uuid)'::regprocedure) into src;
 src:=replace(src,'where id=(p_args->>''target_id'')::uuid and season_id=s','where id=(p_args->>''target_id'')::uuid and season_id=s and destroyed_at is null');
 src:=replace(src,'set origin_id=p.id,destination_id=target.id','set gate_transit=false,origin_id=p.id,destination_id=target.id');execute src;
 select pg_get_functiondef('private.military_process(timestamptz)'::regprocedure) into src;
 src:=replace(src,'select least(coalesce(','select least(coalesce(private.advanced_next_event(s.id),''infinity''),coalesce(');
 src:=replace(src,'perform private.advance_infiltrations(s.id,v_at);','perform private.advance_infiltrations(s.id,v_at);perform private.advance_special_projects(s.id,v_at);');
 src:=replace(src,'perform private.advance_infiltrations(s.id,v_limit);','perform private.advance_infiltrations(s.id,v_limit);perform private.advance_special_projects(s.id,v_limit);');
 src:=replace(src,'    update private.fleets set status=''stationed''',$arrive$
    if exists(select 1 from public.planets where id=f.destination_id and destroyed_at is not null) then update private.fleets set status='destroyed',scouts=0,bombers=0,fighters=0,soldiers=0,ground_soldiers=0 where id=f.id;continue;end if;
    update private.fleets set status='stationed'$arrive$);execute src;
end $patch$;
create function private.special_dashboard() returns jsonb language plpgsql security definer set search_path='' as $$
#variable_conflict use_column
declare e uuid;s uuid;
begin
 e:=private.active_player_id();select season_id into s from public.empires where id=e;
 return jsonb_build_object('planets',coalesce((select jsonb_agg(jsonb_build_object('id',p.id,'name',p.name,'energy',p.energy,'governance',p.governance,'camouflaged',p.camouflaged,'ship_tech',p.ship_tech,'army_tech',p.army_tech,'project',coalesce(to_jsonb(z),'{}'::jsonb),'network',n.name,
 'gate_targets',coalesce((select jsonb_agg(jsonb_build_object('id',q.id,'name',private.military_label(q.id,e),'appearance',q.race||'_'||q.resource)) from private.special_projects g join public.planets q on q.id=g.planet_id where g.gate_network=z.gate_network and g.gate_ready_at<=now() and q.id<>p.id and q.destroyed_at is null),'[]'::jsonb),
 'scan_targets',(select jsonb_agg(to_jsonb(scan_rows)) from(select q.id,private.military_label(q.id,e) name,q.race||'_'||q.resource appearance from public.planets q where q.season_id=s and q.destroyed_at is null and q.id<>p.id order by power(q.x-p.x,2)+power(q.y-p.y,2),q.id limit 30)scan_rows))) from public.planets p left join private.special_projects z on z.planet_id=p.id left join private.gate_networks n on n.id=z.gate_network where p.owner_empire_id=e),'[]'::jsonb),
 'scans',coalesce((select jsonb_agg(to_jsonb(j)-'effective_mode'||jsonb_build_object('target',private.military_label(j.target_id,e))) from private.scan_jobs j where j.empire_id=e),'[]'::jsonb));
end $$;
alter function private.technology_dashboard() rename to technology_dashboard_before_special;
revoke all on function private.technology_dashboard_before_special() from public,anon,authenticated;
create function private.technology_dashboard() returns jsonb language plpgsql security definer set search_path='' as $$
#variable_conflict use_column
declare r jsonb;begin r:=private.technology_dashboard_before_special();return r||jsonb_build_object('special',private.special_dashboard(),'intelligence',private.intelligence_dashboard());end $$;
revoke all on function private.technology_dashboard() from public,anon;grant execute on function private.technology_dashboard() to authenticated;
revoke all on function private.reserve_technology(),private.fleet_technology_origin(),private.set_stasis(uuid,boolean,timestamptz),private.stasis_job_duration(),private.advanced_next_event(uuid),private.track_fleet_departure(),private.disconnect_gate(uuid,timestamptz),private.annihilate_planet(uuid,timestamptz,boolean),private.scan_result(private.scan_jobs),private.advance_special_projects(uuid,timestamptz),private.damage_exploitations(uuid,int,timestamptz),private.massive_bombardment(uuid,timestamptz,jsonb,numeric),private.combat_opponents(jsonb,uuid,text),private.fortification_before_blast(public.planets,timestamptz),private.fortification(public.planets,timestamptz),private.special_dashboard() from public,anon,authenticated;
create function private.military_strength(pid uuid) returns table(side text,space_power numeric,ground_power numeric) language sql stable set search_path='' as $$
 with units as(
 select 'defend'::text side,p.race,p.scouts,p.bombers,p.fighters,case when p.garrison_ready_at<=now() then p.soldiers else 0 end ground,p.ship_tech,p.army_tech,p.camouflaged from public.planets p where p.id=pid
 union all select f.mission,f.race,f.scouts,f.bombers,f.fighters,case when f.ground_ready_at<=now() then f.ground_soldiers else 0 end,f.ship_tech,f.army_tech,f.camouflaged from private.fleets f where f.planet_id=pid and f.status='stationed'),
 totals as(select u.side,sum((scouts+fighters*8)*(case when race='vael' then 1.15 when race='khar' then .85 else 1 end)*(case when camouflaged then .75 else 1 end)) bp,sum(ground*(case when race='khar' then 1.15 when race='vael' then .85 else 1 end)*(case when camouflaged then .75 else 1 end)) gp,sum(ship_tech*(scouts+bombers+fighters))/greatest(1,sum(scouts+bombers+fighters)) sl,sum(army_tech*ground)/greatest(1,sum(ground)) al from units u group by u.side)
 select t.side,t.bp*(1+least(.3,greatest(0,t.sl-coalesce(o.sl,0))*.03)),t.gp*(1+least(.3,greatest(0,t.al-coalesce(o.al,0))*.03))*(case when t.side='defend' then 1+(select private.fortification(p,now()) from public.planets p where p.id=pid) else 1 end) from totals t left join totals o on o.side<>t.side;
$$;
do $patch$ declare src text;begin
 select pg_get_functiondef('private.special_command(text,jsonb,uuid)'::regprocedure) into src;
 src:=replace(src,'select coalesce(sum(scouts+fighters*8) filter(where mission=''attack''),0),coalesce(sum(scouts+fighters*8) filter(where mission=''defend''),0)+p.scouts+p.fighters*8 into ap,dp from private.fleets where planet_id=p.id and status=''stationed'';', 'select coalesce(sum(space_power) filter(where side=''attack''),0),coalesce(sum(space_power) filter(where side=''defend''),0) into ap,dp from private.military_strength(p.id);');execute src;
 select pg_get_functiondef('private.scan_result(private.scan_jobs)'::regprocedure) into src;
 src:=replace(src,'select (p.scouts+p.fighters*8)+coalesce(sum(scouts+fighters*8),0) into v from private.fleets where planet_id=p.id and status=''stationed'';','select coalesce(sum(space_power),0) into v from private.military_strength(p.id);');
 src:=replace(src,'select p.soldiers+coalesce(sum(ground_soldiers),0) into v from private.fleets where planet_id=p.id and status=''stationed'';','select coalesce(sum(ground_power),0) into v from private.military_strength(p.id);');execute src;
 select pg_get_functiondef('private.infiltration_intel(private.infiltrations)'::regprocedure) into src;
 src:=replace(src,'''war'',private.planet_at_war(p.id)', '''stasis'',exists(select 1 from private.special_projects where planet_id=p.id and stasis),''war'',private.planet_at_war(p.id)');execute src;
 select pg_get_functiondef('private.annihilate_planet(uuid,timestamptz,boolean)'::regprocedure) into src;
 src:=replace(src,'delete from private.infiltrations where target_id=pid or origin_id=pid;', 'delete from private.infiltrations where target_id=pid or origin_id=pid;update private.scan_jobs set completed_at=t,result=jsonb_build_object(''aborted'',true) where origin_id=pid and completed_at is null;');execute src;
end $patch$;
-- Direct pre-rollout flights have a known launch time. Redirected historical
-- flights have no recoverable launch history and are not retroactively changed.
update private.fleets f set launched_at=f.departed_at from public.planets p where f.origin_id=p.id and f.status='transit' and f.route_x=p.x and f.route_y=p.y;
revoke all on function private.military_strength(uuid) from public,anon,authenticated;
do $patch$ declare src text;begin
 select pg_get_functiondef('private.fleet_technology_origin()'::regprocedure) into src;
 src:=replace(src,'new.camouflaged:=new.camouflaged or coalesce(p.camouflaged,false);','');execute src;
 select pg_get_functiondef('private.military_command(text,jsonb,uuid)'::regprocedure) into src;
 src:=replace(src,'scouts,bombers,fighters,soldiers,created_at) values(e,s,btrim', 'scouts,bombers,fighters,soldiers,created_at,camouflaged) values(e,s,btrim');
 src:=replace(src,'p.id,p.id,p.id,ns,nb,nf,q,v_at)', 'p.id,p.id,p.id,ns,nb,nf,q,v_at,p.camouflaged)');
 src:=replace(src,'mission,ground_soldiers,created_at) values(e,s,left', 'mission,ground_soldiers,created_at,camouflaged) values(e,s,left');
 src:=replace(src,'f.mission,f.ground_soldiers,v_at)', 'f.mission,f.ground_soldiers,v_at,f.camouflaged)');
 src:=replace(src,$text$elsif p_action='assemble' then$text$, $text$elsif p_action='assemble' then if p.garrison_ready_at>v_at then raise exception 'Réserves N/A.';end if;$text$);execute src;
 select pg_get_functiondef('private.capture_military_state()'::regprocedure) into src;
 src:=replace(src,'ground_soldiers,ground_ready_at) values(old.owner', 'ground_soldiers,ground_ready_at,camouflaged) values(old.owner');
 src:=replace(src,'end,old.garrison_ready_at);','end,old.garrison_ready_at,old.camouflaged);');execute src;
 select pg_get_functiondef('private.technology_command_base(text,jsonb,uuid)'::regprocedure) into src;
 src:=replace(src,'ground_soldiers,ground_ready_at) values(v_e', 'ground_soldiers,ground_ready_at,camouflaged) values(v_e');
 src:=replace(src,'v_p.race,v_energy_planet,v_t.id,v_p.id,''defend'',v_take,v_at+interval ''1 hour'')', 'v_p.race,v_energy_planet,v_t.id,v_p.id,''defend'',v_take,v_at+interval ''1 hour'',v_p.camouflaged)');
 src:=replace(src,'v_group.race,v_energy_planet,v_t.id,v_p.id,''defend'',v_take,v_at+interval ''1 hour'')', 'v_group.race,v_energy_planet,v_t.id,v_p.id,''defend'',v_take,v_at+interval ''1 hour'',v_group.camouflaged)');execute src;
 select pg_get_functiondef('private.advance_infiltrations(uuid,timestamptz)'::regprocedure) into src;
 src:=replace(src,'insert into private.fleets(empire_id,season_id,name,race,supply_planet,planet_id,origin_id,mission,ground_soldiers,ground_ready_at) values(i.empire_id', 'perform set_config(''lw.army_source_level'',f.army_tech::text,true);insert into private.fleets(empire_id,season_id,name,race,supply_planet,planet_id,origin_id,mission,ground_soldiers,ground_ready_at,camouflaged) values(i.empire_id');
 src:=replace(src,'greatest(t+interval ''1 hour'',f.ground_ready_at));','greatest(t+interval ''1 hour'',f.ground_ready_at),f.camouflaged);perform set_config(''lw.army_source_level'','''',true);');execute src;
 select pg_get_functiondef('private.technology_dashboard_base()'::regprocedure) into src;
 src:=replace(src,'then ''clan'' else ''password'' end','then ''clan'' when exists(select 1 from private.infiltrations i where i.empire_id=v_e and i.target_id=p.id and i.level>=90 and not exists(select 1 from private.planet_security z where z.planet_id=i.target_id and(z.mode=''block'' or z.purifying_until>now()))) then ''infiltration'' else ''password'' end');execute src;
end $patch$;
-- Anonymous ownership must not be revealed by the clan's private directory.
do $patch$ declare src text;begin
 select pg_get_functiondef('private.clan_dashboard()'::regprocedure) into src;
 src:=replace(src,'where w.owner_empire_id=m.empire_id','where w.owner_empire_id=m.empire_id and (m.empire_id=e or w.anonymous_until is null or w.anonymous_until<=now())');execute src;
 select pg_get_functiondef('private.set_planet_options(uuid,boolean,boolean)'::regprocedure) into src;
 src:=replace(src,'if p_clan_tag_visible and not exists','if p_clan_tag_visible and v_planet.anonymous_until>now() then raise exception ''Affiliation masquée pendant le contrôle anonyme.'';end if; if p_clan_tag_visible and not exists');execute src;
 select pg_get_functiondef('private.set_stasis(uuid,boolean,timestamptz)'::regprocedure) into src;
 src:=replace(src,'finishes_at=t+(finishes_at-t)*factor::double precision,started_at=t-(t-started_at)*factor::double precision','finishes_at=coalesce(paused_at,t)+(finishes_at-coalesce(paused_at,t))*factor::double precision,started_at=coalesce(paused_at,t)-(coalesce(paused_at,t)-started_at)*factor::double precision');
 src:=replace(src,'and paused_at is null;',';');execute src;
 select pg_get_functiondef('private.advance_special_projects(uuid,timestamptz)'::regprocedure) into src;
 src:=replace(src,'private.ground_superiority(p.id,t) and private.planet_at_war(p.id)','private.planet_at_war(p.id) and (private.ground_superiority(p.id,t) or coalesce((select space_power from private.military_strength(p.id) where side=''attack''),0)>coalesce((select space_power from private.military_strength(p.id) where side=''defend''),0))');execute src;
end $patch$;
alter table private.infiltrations add column last_detection_at timestamptz not null default now();
create function private.detect_captivity(s uuid,t timestamptz) returns void language plpgsql set search_path='' as $$
#variable_conflict use_column
declare i private.infiltrations%rowtype;p public.planets%rowtype;
begin
 for i in select i.* from private.infiltrations i join public.planets p on p.id=i.target_id where p.season_id=s and i.level>=90 and i.drain>0 and i.last_detection_at<=t-interval '1 day' loop
 select * into p from public.planets where id=i.target_id;
 if p.owner_empire_id is not null and random()<.05*private.effective_drain(i)/.35 then insert into private.battle_reports(empire_id,planet_id,occurred_at,event,details) values(p.owner_empire_id,p.id,t,'infiltration_detected',jsonb_build_object('message','Une ponction clandestine a été détectée.'));end if;
 update private.infiltrations set last_detection_at=t where id=i.id;
 end loop;
end $$;
do $patch$ declare src text;begin
 select pg_get_functiondef('private.advance_infiltrations(uuid,timestamptz)'::regprocedure) into src;
 src:=replace(src,'perform private.advance_captivity(s,t);','perform private.advance_captivity(s,t);perform private.detect_captivity(s,t);');execute src;
end $patch$;
revoke all on function private.detect_captivity(uuid,timestamptz) from public,anon,authenticated;
alter table public.planets add column protectorate boolean not null default false,add column protectorate_left_at timestamptz;
-- The existing game has no automatic protectorate period. These constraints apply
-- if that status is assigned, without inventing a duration for new accounts.
create function private.protectorate_transition() returns trigger language plpgsql set search_path='' as $$begin if old.protectorate and not new.protectorate then new.protectorate_left_at:=coalesce(nullif(current_setting('lw.development_at',true),'')::timestamptz,now());end if;return new;end $$;
create trigger protectorate_transition before update of protectorate on public.planets for each row execute function private.protectorate_transition();
do $patch$ declare src text;begin
 select pg_get_functiondef('private.intelligence_command(text,jsonb,uuid)'::regprocedure) into src;
 src:=replace(src,'if n not between 10 and 100 then','if p.protectorate and n>60 then raise exception ''Un protectorat est limité à 60 %% d’infiltration.'';end if;if n not between 10 and 100 then');
 src:=replace(src,'update private.infiltrations set target_level=n where id=i.id;','if n>60 and exists(select 1 from public.planets where id=i.origin_id and protectorate) then raise exception ''Un protectorat est limité à 60 %% d’infiltration.'';end if;update private.infiltrations set target_level=n where id=i.id;');execute src;
 select pg_get_functiondef('private.advance_infiltrations(uuid,timestamptz)'::regprocedure) into src;
 src:=replace(src,'least(i.target_level,i.level+5*days)','least(case when exists(select 1 from public.planets where id=i.origin_id and protectorate) then least(60,i.target_level) else i.target_level end,i.level+5*days)');
 src:=replace(src,'if n>=100 and (select count(*)','if n>=100 and not exists(select 1 from public.planets where id=i.origin_id and protectorate) and (select count(*)');execute src;
 select pg_get_functiondef('private.capture_military_state()'::regprocedure) into src;
 src:=replace(src,'new.captured_at:=','if current_setting(''lw.capture_kind'',true)=''infiltration'' and old.protectorate then new.governance:=''conseil'';new.protectorate:=false;new.protectorate_left_at:=t;end if;new.captured_at:=');execute src;
 select pg_get_functiondef('private.special_command(text,jsonb,uuid)'::regprocedure) into src;
 src:=replace(src,'if z.gate_network is not null then','if p.protectorate or p.protectorate_left_at>t-interval ''15 days'' then raise exception ''Une porte est interdite en protectorat et pendant les quinze jours suivants.'';end if;if z.gate_network is not null then');execute src;
end $patch$;
revoke all on function private.protectorate_transition() from public,anon,authenticated;
create or replace function private.combat_opponents(snapshot jsonb,pid uuid,my_side text) returns jsonb language sql stable set search_path='' as $$
 select coalesce(jsonb_agg(jsonb_build_object('race',q.race,'name',case when q.hidden then 'Forces camouflées' else coalesce(u.username,'Forces neutres') end,'origin',private.military_label(q.origin_id,null))), '[]'::jsonb)
 from(select distinct x.empire_id,x.race,coalesce(f.origin_id,pid) origin_id,(x.camouflaged or exists(select 1 from public.planets p where p.id=pid and p.owner_empire_id=x.empire_id and p.anonymous_until>now())) hidden from jsonb_to_recordset(snapshot)x(id uuid,empire_id uuid,race text,side text,camouflaged boolean) left join private.fleets f on f.id=x.id where side<>my_side)q left join public.empires e on e.id=q.empire_id left join public.profiles u on u.id=e.player_id;
$$;
revoke all on function private.combat_opponents(jsonb,uuid,text) from public,anon,authenticated;
-- Include intelligence income and upkeep in both estimates and accruals, once.
create or replace function private.planet_daily_rates(p_id uuid) returns table(civil numeric,trade numeric,trade_cost numeric,military numeric,fleet numeric) language sql stable set search_path='' as $$
 select b.civil*(1-d.rate)+coalesce(i.income,0),b.trade_cost+(b.trade-b.trade_cost)*(1-d.rate),b.trade_cost,b.military+coalesce(i.upkeep,0)+private.counter_upkeep(p_id),b.fleet
 from private.planet_daily_rates_before_infiltration(p_id)b cross join lateral(select least(1,coalesce(sum(private.effective_drain(i)),0)) rate from private.infiltrations i where i.target_id=p_id)d
 cross join lateral(select sum(private.infiltration_income(z)) income,sum(private.infiltration_upkeep(z)) upkeep from private.infiltrations z where z.origin_id=p_id)i;
$$;
do $patch$ declare src text;a int;b int;begin
 select pg_get_functiondef('private.economy_process_base(timestamptz)'::regprocedure) into src;
 a:=position('union all select i.empire_id,i.origin_id,private.infiltration_income' in src);b:=position(') costs group by' in src);
 if a<1 or b<a then raise exception 'Unexpected intelligence accrual hook';end if;
 execute substring(src from 1 for a-1)||substring(src from b);
end $patch$;
revoke all on function private.planet_daily_rates(uuid) from public,anon,authenticated;
do $patch$ declare src text;begin
 select pg_get_functiondef('private.technology_dashboard_base()'::regprocedure) into src;
 src:=replace(src,'or exists(select 1 from private.planet_teleport_access where planet_id=p.id)', 'or exists(select 1 from private.infiltrations i where i.empire_id=v_e and i.target_id=p.id and i.level>=90 and not exists(select 1 from private.planet_security z where z.planet_id=i.target_id and(z.mode=''block'' or z.purifying_until>now()))) or exists(select 1 from private.planet_teleport_access where planet_id=p.id)');execute src;
end $patch$;
