-- Persist observed technology levels without exposing unit or empire identifiers.
create or replace function private.report_force_totals(p_snapshot jsonb,p_viewer uuid,p_side text,p_group text)
returns jsonb language sql immutable set search_path='' as $$
 with visible as(select * from jsonb_to_recordset(p_snapshot) x(empire_id uuid,side text,race text,ship_tech numeric,army_tech numeric,scouts int,bombers int,fighters int,ground int,cargo int)
 where case p_group when 'own' then side=p_side and empire_id=p_viewer when 'allies' then side=p_side and empire_id is distinct from p_viewer when 'enemies' then side<>p_side else false end),
 breakdown as(select race,v.unit,v.level,sum(v.quantity) quantity from visible cross join lateral(values
 ('soldiers',army_tech,ground::bigint+cargo),('scouts',ship_tech,scouts::bigint),('bombers',ship_tech,bombers::bigint),('fighters',ship_tech,fighters::bigint))v(unit,level,quantity)
 group by race,v.unit,v.level)
 select jsonb_build_object('scouts',coalesce(sum(scouts),0),'bombers',coalesce(sum(bombers),0),'fighters',coalesce(sum(fighters),0),
 'soldiers',coalesce(sum(ground::bigint+cargo),0),'ground',coalesce(sum(ground),0),'embarked',coalesce(sum(cargo),0),
 'units',coalesce((select jsonb_agg(jsonb_build_object('race',race,'unit',unit,'level',level,'quantity',quantity) order by unit,race,level) from breakdown),'[]'::jsonb)) from visible;
$$;
revoke all on function private.report_force_totals(jsonb,uuid,text,text) from public,anon,authenticated;

do $patch$ declare src text;old text;begin
 select pg_get_functiondef('private.resolve_battle(uuid,timestamptz)'::regprocedure) into src;old:=src;
 src:=replace(src,' and (select count(*) from public.planets where owner_empire_id=winner)<12','');
 if src=old then raise exception 'Military conquest limit patch did not match';end if;
 src:=replace(src,$a$jsonb_build_object('opponents',private.combat_opponents(snap,p.id,t.side),$a$,
 $b$jsonb_build_object('outcome',case when event_name='capture' and winner=t.empire_id then 'conquest' when event_name='capture' and old_owner=t.empire_id then 'defeat' when event_name='capture' and t.side='attack' then 'victory' when event_name='capture' then 'defeat' when coalesce((sides->'enemies'->'after'->>'soldiers')::bigint,0)+coalesce((sides->'enemies'->'after'->>'scouts')::bigint,0)+coalesce((sides->'enemies'->'after'->>'bombers')::bigint,0)+coalesce((sides->'enemies'->'after'->>'fighters')::bigint,0)=0 then 'victory' else 'combat' end,'opponents',private.combat_opponents(snap,p.id,t.side),$b$);
 if position('''outcome''' in src)=0 then raise exception 'Battle outcome patch did not match';end if;execute src;
 select pg_get_functiondef('private.advance_infiltrations(uuid,timestamptz)'::regprocedure) into src;old:=src;
 src:=replace(src,' and (select count(*) from public.planets where owner_empire_id=i.empire_id)<12','');
 if src=old then raise exception 'Infiltration conquest limit patch did not match';end if;execute src;
 select pg_get_functiondef('private.military_dashboard_locations()'::regprocedure) into src;
 src:=replace(src,$a$'ground_soldiers',p.soldiers,$a$,$b$'ship_tech',p.ship_tech,'army_tech',p.army_tech,'ground_soldiers',p.soldiers,$b$);
 src:=replace(src,$a$'ground_ready_at',f.ground_ready_at,$a$,$b$'ship_tech',f.ship_tech,'army_tech',f.army_tech,'ground_ready_at',f.ground_ready_at,$b$);execute src;
end $patch$;
