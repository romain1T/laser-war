alter table public.planets add column unit_cohorts jsonb not null default '{}'::jsonb;
alter table private.fleets add column unit_cohorts jsonb not null default '{}'::jsonb;
create function private.cohort_sum(m jsonb) returns bigint language sql immutable set search_path='' as $$select coalesce(sum(value::bigint),0)::bigint from jsonb_each_text(coalesce(m,'{}'))$$;
create function private.cohort_merge(a jsonb,b jsonb,sign int default 1) returns jsonb language sql immutable set search_path='' as $$select coalesce(jsonb_object_agg(k,n) filter(where n>0),'{}') from(select key k,sum(n)::bigint n from(select key,value::bigint n from jsonb_each_text(coalesce(a,'{}')) union all select key,value::bigint*sign from jsonb_each_text(coalesce(b,'{}')))q group by key)x$$;
-- Integer proportional allocation, largest remainders first, stable ties by level.
create function private.cohort_take(m jsonb,n bigint) returns jsonb language sql immutable set search_path='' as $$
 with q as(select key,value::bigint qty from jsonb_each_text(coalesce(m,'{}'))),x as(select key,qty,least(greatest(0,n),sum(qty) over())*qty::numeric/greatest(1,sum(qty) over()) exact from q),y as(select *,floor(exact)::bigint base,row_number() over(order by exact-floor(exact) desc,key) rn from x),z as(select key,base+case when rn<=least(greatest(0,n),(select sum(qty) from q))-sum(base) over() then 1 else 0 end amount from y)select coalesce(jsonb_object_agg(key,amount) filter(where amount>0),'{}') from z;
$$;
create function private.cohort_seed(s bigint,b bigint,f bigint,g bigint,sl numeric,al numeric) returns jsonb language sql immutable set search_path='' as $$select jsonb_build_object('scouts',jsonb_build_object(case when sl=0 then '0' else 'legacy' end,s),'bombers',jsonb_build_object(case when sl=0 then '0' else 'legacy' end,b),'fighters',jsonb_build_object(case when sl=0 then '0' else 'legacy' end,f),'soldiers',jsonb_build_object(case when al=0 then '0' else 'legacy' end,g))$$;
update public.planets set unit_cohorts=private.cohort_seed(scouts,bombers,fighters,soldiers,ship_tech,army_tech);
update private.fleets set unit_cohorts=private.cohort_seed(scouts,bombers,fighters,soldiers::bigint+ground_soldiers,ship_tech,army_tech);
create function private.track_unit_cohorts() returns trigger language plpgsql set search_path='' as $$
declare a jsonb:=case when tg_op='INSERT' then '{}'::jsonb else old.unit_cohorts end;v jsonb:=to_jsonb(new);o jsonb:=case when tg_op='INSERT' then '{}'::jsonb else to_jsonb(old) end;k text;m jsonb;part jsonb;pool jsonb;buf jsonb;before_n bigint;after_n bigint;delta bigint;lev int;trans boolean:=coalesce(current_setting('lw.cohort_transfer',true),'')='on';emp uuid;
begin
 emp:=coalesce((v->>'owner_empire_id')::uuid,(v->>'empire_id')::uuid);
 foreach k in array array['scouts','bombers','fighters','soldiers'] loop
 before_n:=coalesce((o->>k)::bigint,0)+case when k='soldiers' then coalesce((o->>'ground_soldiers')::bigint,0) else 0 end;
 after_n:=coalesce((v->>k)::bigint,0)+case when k='soldiers' then coalesce((v->>'ground_soldiers')::bigint,0) else 0 end;
 m:=coalesce(a->k,'{}');
 if tg_op='INSERT' and private.cohort_sum(new.unit_cohorts->k)=after_n and new.unit_cohorts?k then m:=new.unit_cohorts->k;
 else
 if private.cohort_sum(m)<>before_n then m:=jsonb_build_object('legacy',before_n);end if;
 delta:=after_n-before_n;
 buf:=coalesce(nullif(current_setting('lw.cohort_buffer',true),'')::jsonb,'{}');pool:=coalesce(buf->k,'{}');
 if delta<0 then
 part:=private.cohort_take(m,-delta);m:=private.cohort_merge(m,part,-1);
 if trans then buf:=jsonb_set(buf,array[k],private.cohort_merge(pool,part));perform set_config('lw.cohort_buffer',buf::text,true);end if;
 elsif delta>0 then
 part:=case when trans then private.cohort_take(pool,delta) else '{}'::jsonb end;
 if trans then buf:=jsonb_set(buf,array[k],private.cohort_merge(pool,part,-1));perform set_config('lw.cohort_buffer',buf::text,true);end if;
 lev:=private.tech_level(emp,case when k='soldiers' then 'armies_' else 'ships_' end||new.race);
 m:=private.cohort_merge(m,part);m:=private.cohort_merge(m,jsonb_build_object(lev::text,delta-private.cohort_sum(part)));
 end if;
 end if;
 a:=jsonb_set(a,array[k],m);
 end loop;
 new.unit_cohorts:=a;return new;
end $$;
create trigger zz_unit_cohorts before insert or update on public.planets for each row execute function private.track_unit_cohorts();
create trigger zz_unit_cohorts before insert or update on private.fleets for each row execute function private.track_unit_cohorts();
-- Transfer contexts are enabled only after the economic/combat catch-up has settled.
do $patch$ declare src text;sig text;begin
 foreach sig in array array['private.military_command(text,jsonb,uuid)','private.technology_command_base(text,jsonb,uuid)'] loop
 select pg_get_functiondef(sig::regprocedure) into src;
 src:=replace(src,'perform private.economy_process();','perform private.economy_process();perform set_config(''lw.cohort_transfer'',''on'',true);perform set_config(''lw.cohort_buffer'',''{}'',true);');
 src:=replace(src,'return r;','perform set_config(''lw.cohort_transfer'','''',true);perform set_config(''lw.cohort_buffer'','''',true);return r;');
 src:=replace(src,'return v_result;','perform set_config(''lw.cohort_transfer'','''',true);perform set_config(''lw.cohort_buffer'','''',true);return v_result;');
 src:=replace(src,'elsif delta<0 then','elsif delta<0 then perform set_config(''lw.cohort_buffer'',jsonb_build_object(''soldiers'',private.cohort_take(f.unit_cohorts->''soldiers'',-delta))::text,true);');
 -- Disband adds reserves before clearing the fleet, so seed the transfer buffer explicitly.
 src:=replace(src,$a$elsif p_action='disband' then$a$,$b$elsif p_action='disband' then perform set_config('lw.cohort_buffer',f.unit_cohorts::text,true);$b$);
 -- Dispatch splits ground troops off before clearing them from the departing fleet.
 src:=replace(src,'if f.ground_soldiers>0 then perform set_config(', 'if f.ground_soldiers>0 then perform set_config(''lw.cohort_buffer'',jsonb_build_object(''soldiers'',private.cohort_take(f.unit_cohorts->''soldiers'',f.ground_soldiers))::text,true);perform set_config(');
 execute src;
 end loop;
 -- Preserve remaining reserves through the conquest trigger's insert-before-clear order.
 select pg_get_functiondef('private.capture_military_state()'::regprocedure) into src;
 src:=replace(src,'mission,scouts,bombers,fighters,ground_soldiers,ground_ready_at)', 'mission,scouts,bombers,fighters,ground_soldiers,ground_ready_at,unit_cohorts)');
 src:=replace(src,'old.soldiers,old.garrison_ready_at);','old.soldiers,old.garrison_ready_at,old.unit_cohorts);');execute src;
 -- Gates also split off a ground garrison before the fleet departs.
 select pg_get_functiondef('private.special_command(text,jsonb,uuid)'::regprocedure) into src;
 src:=replace(src,'mission,ground_soldiers,camouflaged) values(e,s,left(f.name', 'mission,ground_soldiers,camouflaged,unit_cohorts) values(e,s,left(f.name');
 src:=replace(src,'f.ground_soldiers,f.camouflaged);','f.ground_soldiers,f.camouflaged,jsonb_build_object(''soldiers'',private.cohort_take(f.unit_cohorts->''soldiers'',f.ground_soldiers)));');execute src;
 select pg_get_functiondef('private.resolve_battle(uuid,timestamptz)'::regprocedure) into src;
 src:=replace(src,'p.camouflaged,false massive_bombing','p.camouflaged,false massive_bombing,p.unit_cohorts');
 src:=replace(src,'f.camouflaged,f.massive_bombing from','f.camouflaged,f.massive_bombing,f.unit_cohorts from');
 src:=replace(src,$a$'cargo',case when$a$,$b$'unit_cohorts',case when (x.value->>'local')::boolean then p.unit_cohorts else f.unit_cohorts end,'cargo',case when$b$);execute src;
 select pg_get_functiondef('private.military_dashboard_locations()'::regprocedure) into src;
 src:=replace(src,$a$'ship_tech',p.ship_tech,$a$,$b$'unit_cohorts',p.unit_cohorts,'ship_tech',p.ship_tech,$b$);
 src:=replace(src,$a$'ship_tech',f.ship_tech,$a$,$b$'unit_cohorts',f.unit_cohorts,'ship_tech',f.ship_tech,$b$);execute src;
end $patch$;
-- Report matrices now persist exact cohort counts, not the averaged engine multiplier.
create or replace function private.report_force_totals(p_snapshot jsonb,p_viewer uuid,p_side text,p_group text) returns jsonb language sql immutable set search_path='' as $$
 with visible as(select * from jsonb_to_recordset(p_snapshot)x(empire_id uuid,side text,race text,scouts int,bombers int,fighters int,ground int,cargo int,unit_cohorts jsonb)
 where case p_group when 'own' then side=p_side and empire_id=p_viewer when 'allies' then side=p_side and empire_id is distinct from p_viewer when 'enemies' then side<>p_side else false end),
 parts as(select race,u.key unit,c.key level,sum(c.value::bigint) quantity from visible cross join lateral jsonb_each(coalesce(unit_cohorts,'{}'))u cross join lateral jsonb_each_text(u.value)c group by race,u.key,c.key)
 select jsonb_build_object('scouts',coalesce(sum(scouts),0),'bombers',coalesce(sum(bombers),0),'fighters',coalesce(sum(fighters),0),'soldiers',coalesce(sum(ground::bigint+cargo),0),'ground',coalesce(sum(ground),0),'embarked',coalesce(sum(cargo),0),
 'units',coalesce((select jsonb_agg(jsonb_build_object('race',race,'unit',unit,'level',case when level='legacy' then null else level::int end,'quantity',quantity) order by unit,race,level) from parts),'[]'::jsonb)) from visible;
$$;
do $patch$ declare src text;begin
 select pg_get_functiondef('private.social_status()'::regprocedure) into src;
 src:=replace(src,'return r||jsonb_build_object(', 'return r||jsonb_build_object(''combat_unread'',exists(select 1 from private.battle_reports where empire_id=e and event in(''battle'',''capture'',''takeover'') and event_seq>(r->''alerts''->>''seen'')::bigint),');execute src;
end $patch$;
revoke all on function private.cohort_sum(jsonb),private.cohort_merge(jsonb,jsonb,int),private.cohort_take(jsonb,bigint),private.cohort_seed(bigint,bigint,bigint,bigint,numeric,numeric),private.track_unit_cohorts() from public,anon,authenticated;

alter function private.military_dashboard() rename to military_dashboard_before_cohorts;
revoke all on function private.military_dashboard_before_cohorts() from public,anon,authenticated;
create function private.military_dashboard() returns jsonb language plpgsql security definer set search_path='' as $$
declare e uuid;r jsonb;research jsonb;begin e:=private.active_player_id();r:=private.military_dashboard_before_cohorts();
 select coalesce(jsonb_agg(jsonb_build_object('id',q.id,'planet',private.military_label(q.planet_id,e),'occurred_at',q.occurred_at,'event',q.event,'details',q.details) order by q.event_seq desc),'[]'::jsonb) into research from(select * from private.battle_reports where empire_id=e and event='research_complete' order by event_seq desc limit 5)q;
 return r||jsonb_build_object('research_notifications',research);end $$;
revoke all on function private.military_dashboard() from public,anon;grant execute on function private.military_dashboard() to authenticated;
