-- Settle elapsed production under the previous rules; no retroactive grants.
select id from public.seasons where status='alpha' for update;
select private.economy_process();
create or replace function private.population_growth_state(p_planet uuid) returns jsonb language plpgsql stable set search_path='' as $$
declare p public.planets%rowtype;war boolean;nearby boolean;occupancy numeric;rate numeric;begin
 select * into p from public.planets where id=p_planet;
 war:=private.planet_at_war(p.id);
 select coalesce(bool_or(private.planet_at_war(n.id)),false) into nearby from(select id from public.planets where season_id=p.season_id and id<>p.id order by power(x-p.x,2)+power(y-p.y,2),id limit 5)n;
 select case when p.trade_capacity=0 then 0 else least(1,coalesce(sum(quantity),0)::numeric/p.trade_capacity) end into occupancy from private.trade_links where status='active' and (planet_a=p.id or planet_b=p.id);
 rate:=case when p.owner_empire_id is null or war then 0 else .01*(1+.02*(greatest(1,least(p.civilization,40))-1))*(case when p.governance='conseil' then 1.2 else .8 end)*(1+.25*occupancy)*(case when nearby then .5 else 1 end) end;
 return jsonb_build_object('daily_rate',rate,'daily_people',p.population*rate,'war',war,'nearby_war',nearby,'trade_occupancy',occupancy);
end $$;
revoke all on function private.population_growth_state(uuid) from public,anon,authenticated;

create or replace function private.recruitment_daily(p public.planets) returns numeric language plpgsql stable set search_path='' as $$
declare g jsonb;occupied numeric;begin
 if p.owner_empire_id is null or not p.recruitment_enabled or p.soldiers>=greatest(1,p.population/1000) then return 0;end if;
 g:=private.population_growth_state(p.id);
 if (g->>'war')::boolean then return 0;end if;
 select coalesce(sum(quantity),0) into occupied from private.trade_links where status='active' and (planet_a=p.id or planet_b=p.id);
 return 2.0*p.population/1000000*p.civilization
  *(case when p.resource='biomasse' then 1.15 else 1 end)
  *(case when p.governance='tyrannie' then 1.2 else .8 end)
  *(1+.25*(g->>'trade_occupancy')::numeric+.5*least(1,occupied/40))
  *(case when (g->>'nearby_war')::boolean then .5 else 1 end);
end $$;
