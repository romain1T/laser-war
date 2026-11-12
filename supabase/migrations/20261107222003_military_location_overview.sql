-- Read-only visibility: owned worlds and worlds where this player's forces are
-- physically stationed. Transit alone never grants reconnaissance.
create function private.force_totals(p_forces jsonb,p_own_only boolean default false,p_side text default null)
returns jsonb language sql immutable set search_path='' as $$
 select jsonb_build_object('fleets',count(*) filter(where kind='fleet' and scouts::bigint+bombers+fighters>0),
 'scouts',coalesce(sum(scouts),0),'bombers',coalesce(sum(bombers),0),'fighters',coalesce(sum(fighters),0),
 'soldiers',coalesce(sum(ground_soldiers::bigint+soldiers),0),'ground',coalesce(sum(ground_soldiers),0),'embarked',coalesce(sum(soldiers),0),
 'ships',coalesce(sum(scouts::bigint+bombers+fighters),0))
 from jsonb_to_recordset(p_forces) as f(kind text,is_own boolean,mission text,scouts int,bombers int,fighters int,soldiers int,ground_soldiers int)
 where (not p_own_only or is_own) and (p_side is null or mission=p_side);
$$;
revoke all on function private.force_totals(jsonb,boolean,text) from public,anon,authenticated;

alter function private.military_dashboard() rename to military_dashboard_base;
revoke all on function private.military_dashboard_base() from public,anon,authenticated;
create function private.military_dashboard() returns jsonb language plpgsql security definer set search_path='' as $$
declare e uuid;r jsonb;locations jsonb;fleets jsonb;
begin
 e:=private.active_player_id();r:=private.military_dashboard_base();
 select coalesce(jsonb_agg(x.value||jsonb_build_object(
 'origin_appearance',o.race||'_'||o.resource,'destination_appearance',d.race||'_'||d.resource) order by x.value->>'created_at'),'[]'::jsonb)
 into fleets from jsonb_array_elements(r->'fleets') x
 left join public.planets o on o.id=(x.value->>'origin_id')::uuid
 left join public.planets d on d.id=(x.value->>'destination_id')::uuid;

 select coalesce(jsonb_agg(jsonb_build_object('id',p.id,'name',private.military_label(p.id,e),'serial',p.serial,
 'is_own',coalesce(p.owner_empire_id=e,false),'race',p.race,'resource',p.resource,'appearance',p.race||'_'||p.resource,
 'civilization',p.civilization,'population',p.population,'fortification',private.fortification(p,now()),
 'stance',case when p.owner_empire_id=e then 'own' when pos.attacking and pos.defending then 'mixed' when pos.attacking then 'attack' else 'defend' end,
 'own_totals',private.force_totals(forces.items,true),'defense',private.force_totals(forces.items,false,'defend'),
 'attack',private.force_totals(forces.items,false,'attack'),'forces',forces.items)
 order by coalesce(p.owner_empire_id=e,false) desc,p.serial),'[]'::jsonb)
 into locations from public.planets p
 cross join lateral(select coalesce(bool_or(f.mission='attack'),false) attacking,coalesce(bool_or(f.mission='defend'),false) defending
 from private.fleets f where f.planet_id=p.id and f.empire_id=e and f.status='stationed' and f.scouts::bigint+f.bombers+f.fighters+f.soldiers+f.ground_soldiers>0)pos
 cross join lateral(select coalesce(jsonb_agg(q.item),'[]'::jsonb) items from(
 select jsonb_build_object('kind','reserve','name','Garnison & réserves','race',p.race,'mission','defend',
 'is_own',coalesce(p.owner_empire_id=e,false),'scouts',p.scouts,'bombers',p.bombers,'fighters',p.fighters,'soldiers',0,
 'ground_soldiers',p.soldiers,'ground_ready_at',p.garrison_ready_at,'unavailable_until','-infinity') item
 where p.scouts::bigint+p.bombers+p.fighters+p.soldiers>0
 union all
 select jsonb_build_object('kind','fleet','name',f.name,'race',f.race,'mission',f.mission,'is_own',f.empire_id=e,
 'scouts',f.scouts,'bombers',f.bombers,'fighters',f.fighters,'soldiers',f.soldiers,'ground_soldiers',f.ground_soldiers,
 'ground_ready_at',f.ground_ready_at,'unavailable_until',f.unavailable_until)
 from private.fleets f where f.planet_id=p.id and f.status='stationed' and f.scouts::bigint+f.bombers+f.fighters+f.soldiers+f.ground_soldiers>0
 )q)forces
 where p.season_id=(select season_id from public.empires where id=e)
 and (p.owner_empire_id=e or pos.attacking or pos.defending);

 return r||jsonb_build_object('fleets',fleets,'locations',locations);
end $$;
revoke all on function private.military_dashboard() from public,anon,authenticated;
grant execute on function private.military_dashboard() to authenticated;
