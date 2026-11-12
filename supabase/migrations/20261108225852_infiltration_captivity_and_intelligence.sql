select id from public.seasons where status='alpha' for update;select private.economy_process();
create table private.planet_ownership(id bigint generated always as identity primary key,planet_id uuid not null references public.planets(id) on delete cascade,empire_id uuid not null references public.empires(id) on delete cascade,since timestamptz not null,until_at timestamptz,founder boolean not null default false);
create index ownership_infiltration on private.planet_ownership(planet_id,empire_id,since,until_at);
insert into private.planet_ownership(planet_id,empire_id,since,founder) select p.id,p.owner_empire_id,p.captured_at,p.created_at=e.created_at from public.planets p join public.empires e on e.id=p.owner_empire_id;
create table private.infiltrations(id uuid primary key default gen_random_uuid(),empire_id uuid not null references public.empires(id) on delete cascade,origin_id uuid not null references public.planets(id) on delete cascade,target_id uuid not null references public.planets(id) on delete cascade,level numeric not null default 0 check(level between 0 and 100),target_level int not null default 30 check(target_level between 10 and 100),trade_dependent boolean not null default true,drain numeric not null default 0 check(drain between 0 and .7),drain_changed_at timestamptz,last_at timestamptz not null default now(),created_at timestamptz not null default now(),unique(empire_id,target_id),check(origin_id<>target_id));
create index infiltrations_target on private.infiltrations(target_id);
create table private.planet_security(planet_id uuid primary key references public.planets(id) on delete cascade,mode text not null default 'off' check(mode in('off','block','clear')),accuracy int not null default 50 check(accuracy between 1 and 100),next_check_at timestamptz not null default now()+interval '1 day',purifying_until timestamptz,civ_loss_fraction numeric not null default 0,pop_loss_fraction numeric not null default 0);
create table private.intelligence_commands(empire_id uuid not null references public.empires(id) on delete cascade,request_id uuid not null,payload jsonb not null,result jsonb not null,primary key(empire_id,request_id));
alter table private.planet_ownership enable row level security;alter table private.infiltrations enable row level security;alter table private.planet_security enable row level security;alter table private.intelligence_commands enable row level security;
revoke all on private.planet_ownership,private.infiltrations,private.planet_security,private.intelligence_commands from public,anon,authenticated;
create function private.log_planet_ownership() returns trigger language plpgsql set search_path='' as $$
#variable_conflict use_column
declare t timestamptz:=coalesce(nullif(current_setting('lw.development_at',true),'')::timestamptz,now());begin
 if tg_op='INSERT' then if new.owner_empire_id is not null then insert into private.planet_ownership(planet_id,empire_id,since,founder) values(new.id,new.owner_empire_id,t,true);end if;
 elsif new.owner_empire_id is distinct from old.owner_empire_id then
 update private.planet_ownership set until_at=t where planet_id=new.id and until_at is null;
 if new.owner_empire_id is not null then insert into private.planet_ownership(planet_id,empire_id,since) values(new.id,new.owner_empire_id,t);end if;
 delete from private.infiltrations where origin_id=new.id or (target_id=new.id and empire_id=new.owner_empire_id);
 delete from private.planet_security where planet_id=new.id;
 end if;return new;end $$;
create trigger z_planet_ownership after insert or update of owner_empire_id on public.planets for each row execute function private.log_planet_ownership();
create function private.infiltration_allowed(e uuid,o uuid,t uuid) returns boolean language sql stable set search_path='' as $$
 select exists(select 1 from public.planets p join public.planets q on q.id=t where p.id=o and p.owner_empire_id=e and q.owner_empire_id is distinct from e and p.season_id=q.season_id) and (
 exists(select 1 from private.trade_links l where l.status='active' and l.planet_a=least(o,t) and l.planet_b=greatest(o,t)) or exists(select 1 from private.planet_ownership h where h.planet_id=t and h.empire_id=e and(h.founder or (coalesce(h.until_at,now())>=now()-interval '200 days' and coalesce(h.until_at,now())-greatest(h.since,now()-interval '200 days')>=interval '2 days'))));
$$;
create function private.infiltration_discount(e uuid,civ int) returns numeric language sql stable set search_path='' as $$select case when civ<=greatest(case when private.tech_level(e,'genetics_1')>0 then 6 else 0 end,case when private.tech_level(e,'genetics_2')>0 then 7 else 0 end,case when private.tech_level(e,'mind_duplication')>0 then 9 else 0 end,case when private.tech_level(e,'mind_control')>0 then 11 else 0 end,case when private.tech_level(e,'infiltration_advanced')>0 then private.tech_level(e,'infiltration_advanced')+7 else 0 end) then .6 else 1 end$$;
create function private.counter_discount(e uuid) returns numeric language sql stable set search_path='' as $$select 1-greatest(case when private.tech_level(e,'genetics_1')>0 then .07 else 0 end,case when private.tech_level(e,'genetics_2')>0 then .15 else 0 end,case when private.tech_level(e,'mind_duplication')>0 then .25 else 0 end,case when private.tech_level(e,'mind_control')>0 then .35 else 0 end)$$;
create function private.effective_drain(i private.infiltrations) returns numeric language sql stable set search_path='' as $$
 select case when i.level<90 or coalesce(s.mode='block' or s.purifying_until>coalesce(nullif(current_setting('lw.rate_at',true),'')::timestamptz,now()),false) then 0 else i.drain*least(1,(case when p.owner_empire_id is null then .7 else .35 end)/greatest(.00001,(select coalesce(sum(x.drain),0) from private.infiltrations x where x.target_id=i.target_id and x.level>=90))) end from public.planets p left join private.planet_security s on s.planet_id=p.id where p.id=i.target_id;
$$;
create function private.infiltration_upkeep(i private.infiltrations) returns numeric language sql stable set search_path='' as $$select 1000*p.civilization*private.infiltration_discount(i.empire_id,p.civilization)*case when i.level>=i.target_level then .1 else 1 end from public.planets p where p.id=i.target_id$$;
create function private.intelligence_command(p_action text,p_args jsonb,p_request_id uuid) returns jsonb language plpgsql security definer set search_path='' as $$
#variable_conflict use_column

declare e uuid;s uuid;p public.planets%rowtype;target public.planets%rowtype;i private.infiltrations%rowtype;payload jsonb;r jsonb;prev private.intelligence_commands%rowtype;n int;rate numeric;mode text;
begin
 select id into s from public.seasons where status='alpha' for update;e:=private.active_player_id();if p_request_id is null then raise exception 'Identifiant requis.';end if;
 payload:=jsonb_build_object('action',p_action,'args',p_args);select * into prev from private.intelligence_commands where empire_id=e and request_id=p_request_id;
 if found then if prev.payload<>payload then raise exception 'Identifiant déjà utilisé.';end if;return prev.result;end if;
 perform private.economy_process();if private.tech_level(e,'infiltration')=0 then raise exception 'Recherchez l’infiltration.';end if;
 if p_action in('infiltrate','security','purify','purify_cancel') then
 select * into p from public.planets where id=(p_args->>'planet_id')::uuid and owner_empire_id=e for update;if not found then raise exception 'Planète inaccessible.';end if;
 if private.ground_superiority(p.id,now()) then raise exception 'Contrôle de la planète contesté.';end if;
 if p_action='infiltrate' then
 select * into target from public.planets where id=(p_args->>'target_id')::uuid for update;
 if not private.infiltration_allowed(e,p.id,target.id) then raise exception 'Liaison commerciale ou historique de contrôle requis.';end if;
 if exists(select 1 from private.planet_security where planet_id=target.id and(mode='block' or purifying_until>now())) then raise exception 'Infiltration impossible sur cette planète.';end if;
 n:=coalesce((p_args->>'target_level')::int,30);if n not between 10 and 100 then raise exception 'Cible entre 10 et 100 %%.';end if;
 insert into private.infiltrations(empire_id,origin_id,target_id,target_level,trade_dependent) values(e,p.id,target.id,n,not exists(select 1 from private.planet_ownership h where h.planet_id=target.id and h.empire_id=e and(h.founder or (coalesce(h.until_at,now())>=now()-interval '200 days' and coalesce(h.until_at,now())-greatest(h.since,now()-interval '200 days')>=interval '2 days')))) returning * into i;
 elsif p_action='security' then
 mode:=p_args->>'mode';n:=coalesce((p_args->>'accuracy')::int,50);if mode is null or mode not in('off','block','clear') or n not between 1 and 100 then raise exception 'Mode de sécurité invalide.';end if;
 insert into private.planet_security(planet_id,mode,accuracy) values(p.id,mode,n) on conflict(planet_id) do update set mode=excluded.mode,accuracy=excluded.accuracy;
 elsif p_action='purify' then
 if p.governance<>'tyrannie' then raise exception 'La purification demande la Tyrannie.';end if;
 if exists(select 1 from private.planet_security where planet_id=p.id and purifying_until>now()) then raise exception 'Purification déjà en cours.';end if;
 delete from private.infiltrations where origin_id=p.id;
 insert into private.planet_security(planet_id,purifying_until) values(p.id,now()+interval '7 days') on conflict(planet_id) do update set purifying_until=excluded.purifying_until;
 else update private.planet_security set purifying_until=null where planet_id=p.id;end if;
 else
 select * into i from private.infiltrations where id=(p_args->>'infiltration_id')::uuid and empire_id=e for update;if not found then raise exception 'Infiltration inaccessible.';end if;
 if private.ground_superiority(i.origin_id,now()) then raise exception 'Contrôle de la planète d’origine contesté.';end if;
 if p_action='infiltration_cancel' then delete from private.infiltrations where id=i.id;
 elsif p_action='infiltration_target' then
 n:=(p_args->>'target_level')::int;if n is null or n not between 10 and 100 then raise exception 'Cible entre 10 et 100 %%.';end if;update private.infiltrations set target_level=n where id=i.id;
 elsif p_action='drain' then
 select * into target from public.planets where id=i.target_id;
 rate:=(p_args->>'rate')::numeric/100;
 if i.level<90 or rate is null or rate<0 or rate>(case when target.owner_empire_id is null then .7 else .35 end) then raise exception 'Drainage non disponible ou taux invalide.';end if;
 if i.drain_changed_at>now()-interval '24 hours' then raise exception 'Le drainage ne peut changer qu’une fois par 24 heures.';end if;
 update private.infiltrations set drain=rate,drain_changed_at=now() where id=i.id;insert into private.planet_security(planet_id,last_drain_at) values(i.target_id,now()) on conflict(planet_id) do update set last_drain_at=excluded.last_drain_at;
 else raise exception 'Action inconnue.';end if;
 end if;
 r:=jsonb_build_object('ok',true,'id',i.id);insert into private.intelligence_commands values(e,p_request_id,payload,r);return r;
end $$;
create function public.intelligence_command(p_action text,p_args jsonb,p_request_id uuid) returns jsonb language sql security invoker set search_path='' as $$select private.intelligence_command(p_action,p_args,p_request_id)$$;
revoke all on function public.intelligence_command(text,jsonb,uuid),private.intelligence_command(text,jsonb,uuid) from public,anon;
grant execute on function public.intelligence_command(text,jsonb,uuid),private.intelligence_command(text,jsonb,uuid) to authenticated;
create function private.advance_infiltrations(s uuid,t timestamptz) returns void language plpgsql set search_path='' as $$
#variable_conflict use_column

declare i private.infiltrations%rowtype;p public.planets%rowtype;sec private.planet_security%rowtype;n numeric;days numeric;dr numeric;loss numeric;civ_loss numeric;old_e uuid;f record;
begin
 perform set_config('lw.development_at',t::text,true);
 for sec in select z.* from private.planet_security z join public.planets p on p.id=z.planet_id where p.season_id=s loop
 if sec.purifying_until<=t then delete from private.infiltrations where target_id=sec.planet_id;update private.planet_security set purifying_until=null where planet_id=sec.planet_id;end if;
 if sec.mode='clear' and sec.next_check_at<=t then
 delete from private.infiltrations where target_id=sec.planet_id and level<100 and random()<sec.accuracy/100.0;
 update private.planet_security set next_check_at=sec.next_check_at+interval '1 day' where planet_id=sec.planet_id;
 end if;end loop;
 for i in select f.* from private.infiltrations f join public.planets p on p.id=f.target_id where p.season_id=s and f.last_at<t order by f.id for update of f loop
 if i.trade_dependent and i.level<30 and not exists(select 1 from private.trade_links where status='active' and planet_a=least(i.origin_id,i.target_id) and planet_b=greatest(i.origin_id,i.target_id)) then delete from private.infiltrations where id=i.id;continue;end if;
 select * into sec from private.planet_security where planet_id=i.target_id;
 if coalesce(sec.mode='block' or sec.purifying_until>t,false) then update private.infiltrations set last_at=t where id=i.id;continue;end if;
 days:=extract(epoch from(t-i.last_at))/86400;
 n:=greatest(i.level,least(i.target_level,i.level+5*days));update private.infiltrations set level=n,last_at=t where id=i.id;
 if n>=100 and (select count(*) from public.planets where owner_empire_id=i.empire_id)<12 then
 select * into p from public.planets where id=i.target_id for update;old_e:=p.owner_empire_id;
 -- Ground armies transfer; the former controller's orbital ships do not.
 for f in select * from private.fleets where planet_id=p.id and status='stationed' and empire_id=old_e and ground_soldiers>0 loop
 insert into private.fleets(empire_id,season_id,name,race,supply_planet,planet_id,origin_id,mission,ground_soldiers,ground_ready_at) values(i.empire_id,s,'Forces intégrées',f.race,p.id,p.id,p.id,'defend',f.ground_soldiers,greatest(t+interval '1 hour',f.ground_ready_at));
 update private.fleets set ground_soldiers=0 where id=f.id;end loop;
 perform set_config('lw.capture_kind','infiltration',true);
 update public.planets set owner_empire_id=i.empire_id,rename_available=true,clan_tag_visible=false where id=p.id;
 perform set_config('lw.capture_kind','',true);
 if old_e is not null then insert into private.battle_reports(empire_id,planet_id,occurred_at,event,details) values(old_e,p.id,t,'takeover',jsonb_build_object('new_owner','Contrôleur anonyme','infiltration',true));end if;
 insert into private.battle_reports(empire_id,planet_id,occurred_at,event,details) values(i.empire_id,p.id,t,'takeover',jsonb_build_object('new_owner','Vous','infiltration',true));
 end if;
 end loop;
end $$;
-- Preserve fortifications, government and reserve armies on a covert takeover.
do $patch$ declare src text;begin
 select pg_get_functiondef('private.capture_military_state()'::regprocedure) into src;
 src:=replace(src,'new.captured_at:=t;','new.captured_at:=case when current_setting(''lw.capture_kind'',true)=''infiltration'' then old.captured_at else t end;');
 src:=replace(src,'old.scouts::bigint+old.bombers+old.fighters+old.soldiers>0','old.scouts::bigint+old.bombers+old.fighters+(case when current_setting(''lw.capture_kind'',true)=''infiltration'' then 0 else old.soldiers end)>0');
 src:=replace(src,$text$'defend',old.scouts,old.bombers,old.fighters,old.soldiers,old.garrison_ready_at$text$,$text$'defend',old.scouts,old.bombers,old.fighters,case when current_setting('lw.capture_kind',true)='infiltration' then 0 else old.soldiers end,old.garrison_ready_at$text$);
 src:=replace(src,'new.soldiers:=0;','new.soldiers:=case when current_setting(''lw.capture_kind'',true)=''infiltration'' then old.soldiers else 0 end;');
 src:=replace(src,$text$if new.governance='tyrannie' then$text$,$text$if new.governance='tyrannie' and coalesce(current_setting('lw.capture_kind',true),'')<>'infiltration' then$text$);
 src:=replace(src,'case when hidden then t+',$text$case when hidden or current_setting('lw.capture_kind',true)='infiltration' then t+$text$);
 src:=replace(src,'if not hidden then',$text$if not hidden and coalesce(current_setting('lw.capture_kind',true),'')<>'infiltration' then$text$);
 execute src;
end $patch$;
create function private.infiltration_intel(i private.infiltrations) returns jsonb language plpgsql stable set search_path='' as $$
#variable_conflict use_column

declare p public.planets%rowtype;r jsonb:='{}';a boolean;
begin
 select * into p from public.planets where id=i.target_id;a:=p.anonymous_until>now();
 if i.level>=10 then r:=r||jsonb_build_object('population',p.population,'civilization_investments',coalesce((select jsonb_agg(jsonb_build_object('target',target_level,'finishes_at',finishes_at)) from private.civilization_jobs where planet_id=p.id and cancelled_at is null and completed_at is null),'[]'::jsonb));end if;
 if i.level>=20 then r:=r||jsonb_build_object('trade_capacity',p.trade_capacity,'trade_links',coalesce((select jsonb_agg(jsonb_build_object('planet',private.military_label(case when planet_a=p.id then planet_b else planet_a end,i.empire_id),'quantity',quantity,'status',status)) from private.trade_links where status in('active','pending') and p.id in(planet_a,planet_b)),'[]'::jsonb),'war',private.planet_at_war(p.id),'purifying',exists(select 1 from private.planet_security where planet_id=p.id and purifying_until>now()));end if;
 if i.level>=30 then r:=r||jsonb_build_object('owner',case when a then 'Contrôleur anonyme' else (select u.username from public.empires e join public.profiles u on u.id=e.player_id where e.id=p.owner_empire_id) end,'clan',case when not coalesce(a,false) then(select c.name from private.clan_memberships m join public.clans c on c.id=m.clan_id where m.empire_id=p.owner_empire_id)end);end if;
 if i.level>=40 then r:=r||jsonb_build_object('energy',p.energy,'energy_max',p.energy_max);end if;
 if i.level>=50 then r:=r||jsonb_build_object('forces',coalesce((select jsonb_agg(x) from(select p.race,'defend'::text mission,p.scouts,p.bombers,p.fighters,p.soldiers ground_soldiers,0 soldiers union all select f.race,f.mission,f.scouts,f.bombers,f.fighters,f.ground_soldiers,f.soldiers from private.fleets f where planet_id=p.id and status='stationed')x),'[]'::jsonb));end if;
 if i.level>=70 then r:=r||jsonb_build_object('infiltrations',coalesce((select jsonb_agg(jsonb_build_object('level',level,'target_level',target_level)) from private.infiltrations where target_id=p.id),'[]'::jsonb));end if;
 if i.level>=90 then r:=r||jsonb_build_object('teleport_access',true);end if;
 return r;
end $$;
create function private.intelligence_dashboard() returns jsonb language plpgsql security definer set search_path='' as $$
#variable_conflict use_column

declare e uuid;s uuid;
begin
 e:=private.active_player_id();select season_id into s from public.empires where id=e;perform private.economy_process();
 return jsonb_build_object('unlocked',private.tech_level(e,'infiltration')>0,'infiltrations',coalesce((select jsonb_agg(to_jsonb(i)||jsonb_build_object('target',private.military_label(i.target_id,e),'origin',private.military_label(i.origin_id,e),'upkeep',private.infiltration_upkeep(i),'effective_drain',private.effective_drain(i),'intel',private.infiltration_intel(i))) from private.infiltrations i where i.empire_id=e),'[]'::jsonb),
 'planets',coalesce((select jsonb_agg(jsonb_build_object('id',p.id,'name',p.name,'governance',p.governance,'security',coalesce((select to_jsonb(z)-'civ_loss_fraction'-'pop_loss_fraction' from private.planet_security z where z.planet_id=p.id),'{}'::jsonb),'counter_discount',private.counter_discount(e),'targets',coalesce((select jsonb_agg(jsonb_build_object('id',q.id,'name',private.military_label(q.id,e))) from public.planets q where q.season_id=s and private.infiltration_allowed(e,p.id,q.id)),'[]'::jsonb))) from public.planets p where p.owner_empire_id=e),'[]'::jsonb));
end $$;
create function public.intelligence_dashboard() returns jsonb language sql security invoker set search_path='' as $$select private.intelligence_dashboard()$$;
revoke all on function public.intelligence_dashboard(),private.intelligence_dashboard() from public,anon;grant execute on function public.intelligence_dashboard(),private.intelligence_dashboard() to authenticated;
revoke all on function private.log_planet_ownership(),private.infiltration_allowed(uuid,uuid,uuid),private.infiltration_discount(uuid,int),private.counter_discount(uuid),private.effective_drain(private.infiltrations),private.infiltration_upkeep(private.infiltrations),private.advance_infiltrations(uuid,timestamptz),private.infiltration_intel(private.infiltrations) from public,anon,authenticated;
alter table private.planet_security add column last_drain_at timestamptz not null default now();
create function private.counter_upkeep(pid uuid) returns numeric language sql stable set search_path='' as $$select coalesce((select p.civilization*private.counter_discount(p.owner_empire_id)*case z.mode when 'block' then 2000 when 'clear' then 1000*z.accuracy/100.0 else 0 end from private.planet_security z join public.planets p on p.id=z.planet_id where z.planet_id=pid),0)$$;
alter function private.planet_daily_rates(uuid) rename to planet_daily_rates_before_infiltration;
create function private.planet_daily_rates(p_id uuid) returns table(civil numeric,trade numeric,trade_cost numeric,military numeric,fleet numeric) language sql stable set search_path='' as $$
 select b.civil*(1-d.rate),b.trade_cost+(b.trade-b.trade_cost)*(1-d.rate),b.trade_cost,b.military,b.fleet from private.planet_daily_rates_before_infiltration(p_id)b cross join lateral(select least(1,coalesce(sum(private.effective_drain(i)),0)) rate from private.infiltrations i where i.target_id=p_id)d;
$$;
create function private.infiltration_income(i private.infiltrations) returns numeric language sql stable set search_path='' as $$select (r.civil+r.trade-r.trade_cost)*private.effective_drain(i) from private.planet_daily_rates_before_infiltration(i.target_id)r$$;
-- Purification blocks both ends of every trade route, including a partner's income.
do $patch$ declare src text;begin
 select pg_get_functiondef('private.planet_daily_rates_before_infiltration(uuid)'::regprocedure) into src;
 src:=replace(src,'b.blockaded or b.trade_resumes_at>', 'exists(select 1 from private.planet_security ps where ps.planet_id=b.id and ps.purifying_until>coalesce(nullif(current_setting(''lw.rate_at'',true),'''')::timestamptz,now())) or b.blockaded or b.trade_resumes_at>');execute src;
 select pg_get_functiondef('private.economy_process_base(timestamptz)'::regprocedure) into src;
 if position(') costs group by' in src)=0 then raise exception 'Unexpected economy accrual definition';end if;
 src:=replace(src,') costs group by',$extra$
 union all select i.empire_id,i.origin_id,private.infiltration_income(i)*d.seconds/86400,0,0,private.infiltration_upkeep(i)*d.seconds/86400,0
 from private.infiltrations i join public.planets ip on ip.id=i.origin_id cross join lateral(select greatest(0,extract(epoch from(v_until-greatest(v_cursor,i.created_at)))) seconds)d where ip.season_id=v_id
 union all select p.owner_empire_id,p.id,0,0,0,private.counter_upkeep(p.id)*d.seconds/86400,0
 from public.planets p cross join lateral(select greatest(0,extract(epoch from(v_until-v_cursor))) seconds)d where p.season_id=v_id and p.owner_empire_id is not null
 ) costs group by$extra$);execute src;
end $patch$;
create function private.advance_captivity(s uuid,t timestamptz) returns void language plpgsql set search_path='' as $$
#variable_conflict use_column

declare p public.planets%rowtype;sec private.planet_security%rowtype;ratio numeric;days numeric;poploss numeric;civloss numeric;
begin
 for p in select p.* from public.planets p where season_id=s and exists(select 1 from private.infiltrations where target_id=p.id and level>=90 and drain>0) loop
 insert into private.planet_security(planet_id) values(p.id) on conflict do nothing;
 select * into sec from private.planet_security where planet_id=p.id for update;
 days:=greatest(0,extract(epoch from(t-sec.last_drain_at))/86400);
 select coalesce(sum(private.effective_drain(i)),0)/(case when p.owner_empire_id is null then .7 else .35 end) into ratio from private.infiltrations i where target_id=p.id;
 poploss:=sec.pop_loss_fraction+p.population*.005*ratio*days;civloss:=sec.civ_loss_fraction+ratio*days/30;
 perform set_config('lw.captivity_damage','on',true);
 update public.planets set population=greatest(0,population-floor(poploss)::bigint),civilization=greatest(1,civilization-floor(civloss)::int) where id=p.id;
 perform set_config('lw.captivity_damage','',true);
 update private.planet_security set pop_loss_fraction=poploss-floor(poploss),civ_loss_fraction=civloss-floor(civloss),last_drain_at=t where planet_id=p.id;
 end loop;
end $$;
do $patch$ declare src text;begin
 select pg_get_functiondef('private.neutral_world_rules()'::regprocedure) into src;
 src:=replace(src,'begin', 'begin if current_setting(''lw.captivity_damage'',true)=''on'' then return new;end if;');execute src;
 select pg_get_functiondef('private.advance_infiltrations(uuid,timestamptz)'::regprocedure) into src;
 src:=replace(src,'perform set_config(''lw.development_at'',t::text,true);','perform set_config(''lw.development_at'',t::text,true); perform private.advance_captivity(s,t);');execute src;
 select pg_get_functiondef('private.military_process(timestamptz)'::regprocedure) into src;
 src:=replace(src,'perform private.research_complete(s.id,v_at);','perform private.research_complete(s.id,v_at); perform private.advance_infiltrations(s.id,v_at);');
 src:=replace(src,'perform private.advance_planet_development(s.id,v_limit);','perform private.advance_planet_development(s.id,v_limit); perform private.advance_infiltrations(s.id,v_limit);');execute src;
 select pg_get_functiondef('private.technology_command_base(text,jsonb,uuid)'::regprocedure) into src;
 src:=replace(src,'v_allowed:=v_clan is not null and v_other_clan is not null and v_clan=v_other_clan;','v_allowed:=(v_clan is not null and v_other_clan is not null and v_clan=v_other_clan) or exists(select 1 from private.infiltrations i where i.empire_id=v_e and i.target_id=v_foreign and i.level>=90 and not exists(select 1 from private.planet_security z where z.planet_id=i.target_id and(z.mode=''block'' or z.purifying_until>v_at)));');execute src;
end $patch$;
revoke all on function private.planet_daily_rates(uuid),private.planet_daily_rates_before_infiltration(uuid),private.counter_upkeep(uuid),private.infiltration_income(private.infiltrations),private.advance_captivity(uuid,timestamptz) from public,anon,authenticated;
