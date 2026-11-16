-- All existing worlds are level 1; this does not reset any player state.
select private.economy_process();
alter table public.planets add constraint civilization_maximum check(civilization<=40);
create function private.civilization_trade_multiplier(p_level integer) returns numeric language sql immutable strict set search_path='' as $$
 select 1+(greatest(1,least(p_level,40))-1)*.05;
$$;
revoke all on function private.civilization_trade_multiplier(integer) from public,anon,authenticated;
create or replace function private.planet_daily_rates(p_id uuid)
returns table(civil numeric,trade numeric,trade_cost numeric,military numeric,fleet numeric)
language sql stable set search_path='' as $$
 select p.population*.02*(case when p.resource='aurite' then 1.15 else 1 end),
 coalesce(t.cost,0)+(coalesce(t.gross,0)-coalesce(t.cost,0))*private.civilization_trade_multiplier(p.civilization)*(case when p.resource='aurite' then 1.15 else 1 end),
 coalesce(t.cost,0),p.soldiers*2::numeric,(p.scouts::numeric*20+p.bombers::numeric*60+p.fighters::numeric*80)
 from public.planets p left join lateral(
 select sum(l.quantity*1500)::numeric gross,sum(l.quantity*least(l.distance,1000))::numeric cost
 from private.trade_links l where l.status='active' and(l.planet_a=p.id or l.planet_b=p.id)
 ) t on true where p.id=p_id;
$$;

create or replace function private.trade_dashboard(p_planet_id uuid) returns jsonb language plpgsql security definer set search_path='' as $$
declare r jsonb;dest jsonb;links jsonb;reserved integer;v_civ integer;
begin
 r:=private.trade_dashboard_base(p_planet_id);
 select civilization into v_civ from public.planets where id=p_planet_id;
 select coalesce(jsonb_agg(d.value||jsonb_build_object('name',p.name,'civilization',p.civilization,'available',greatest(0,p.trade_capacity-private.trade_used(p.id))) order by d.position),'[]'::jsonb)
 into dest from jsonb_array_elements(r->'destinations') with ordinality d(value,position) join public.planets p on p.id=(d.value->>'id')::uuid;
 select coalesce(jsonb_agg(z.value||jsonb_build_object('name',p.name,'civilization',p.civilization,'available',greatest(0,p.trade_capacity-private.trade_used(p.id)),
 'increase',case when i.id is null then null else jsonb_build_object('quantity',i.quantity,'expires_at',i.expires_at,'can_review',i.requester_planet<>p_planet_id) end) order by z.value->>'created_at' desc),'[]'::jsonb)
 into links from jsonb_array_elements(r->'links') z join public.planets p on p.id=(z.value->>'other_id')::uuid
 left join private.trade_increases i on i.link_id=(z.value->>'id')::uuid and i.status='pending' and i.expires_at>now() and z.value->>'status'='active';
 select coalesce(sum(i.quantity),0)::integer into reserved from private.trade_increases i join private.trade_links l on l.id=i.link_id where i.status='pending' and i.expires_at>now() and l.status='active' and(l.planet_a=p_planet_id or l.planet_b=p_planet_id);
 r:=jsonb_set(r,'{planet,reserved}',to_jsonb((r#>>'{planet,reserved}')::integer+reserved));
 r:=jsonb_set(r,'{planet,civilization}',to_jsonb(v_civ));
 return r||jsonb_build_object('destinations',dest,'links',links);
end $$;


create or replace function private.trade_dashboard_base(p_planet_id uuid) returns jsonb language plpgsql security definer set search_path='' as $$
declare v_player uuid:=private.active_player_id();v_planet public.planets%rowtype;v_bonus numeric;v_result jsonb;
begin
 select * into v_planet from public.planets where id=p_planet_id and owner_empire_id=v_player;
 if not found then raise exception 'Planète inaccessible.' using errcode='42501'; end if;
 perform 1 from public.seasons where id=v_planet.season_id for update;
 perform private.economy_process();
 -- Reload after settlement / automatic acceptance.
 select * into v_planet from public.planets where id=p_planet_id and owner_empire_id=v_player;
 v_bonus:=(case when v_planet.resource='aurite' then 1.15 else 1 end)*private.civilization_trade_multiplier(v_planet.civilization);
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
