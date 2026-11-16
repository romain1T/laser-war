-- Keep fractional merit, but make the displayed total equal its displayed components.
create or replace function private.player_rank(p_empire uuid) returns jsonb language plpgsql stable set search_path='' as $$
declare civ bigint;advanced int;raw_production numeric;production numeric;combat numeric;total bigint;current_rank jsonb;next_rank jsonb;units jsonb;
begin
 select coalesce(sum(civilization),0)*100,count(*) filter(where civilization>=15) into civ,advanced from public.planets where owner_empire_id=p_empire;
 select .2*(produced_soldiers::numeric+4*produced_scouts::numeric+24*produced_bombers::numeric+32*produced_fighters::numeric),destroyed_points,
 jsonb_build_object('soldiers',produced_soldiers,'scouts',produced_scouts,'bombers',produced_bombers,'fighters',produced_fighters) into raw_production,combat,units from private.player_merit where empire_id=p_empire;
 raw_production:=coalesce(raw_production,0);combat:=coalesce(combat,0);production:=least(raw_production,civ*.4);total:=civ+floor(production)::bigint+floor(combat)::bigint;
 select x into current_rank from jsonb_array_elements(private.rank_catalog())x where (x->>'threshold')::bigint<=total and ((x->>'tier')::int<10 or (advanced>=3 and combat>=2000)) order by (x->>'tier')::int desc limit 1;
 select x into next_rank from jsonb_array_elements(private.rank_catalog())x where (x->>'tier')::int=(current_rank->>'tier')::int+1;
 return jsonb_build_object('name',current_rank->>'name','tier',(current_rank->>'tier')::int,'score',total,'civilization_points',civ,'production_points',floor(production),'raw_production_points',floor(raw_production),'combat_points',floor(combat),'advanced_worlds',advanced,'produced_units',coalesce(units,'{"soldiers":0,"scouts":0,"bombers":0,"fighters":0}'::jsonb),'next',next_rank,'catalog',private.rank_catalog());
end $$;

select private.refresh_ranks(id) from public.seasons where status='alpha';
