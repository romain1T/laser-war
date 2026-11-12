-- Settle earned income before applying the new compatibility rule.
select private.economy_process();
update private.trade_links l set status='cancelled',closed_at=now()
from public.planets a,public.planets b
where a.id=l.planet_a and b.id=l.planet_b and a.resource=b.resource and l.status in('active','pending');
update private.trade_increases i set status='cancelled' from private.trade_links l where l.id=i.link_id and l.status='cancelled' and i.status='pending';

create function private.trade_resource_compatibility() returns trigger language plpgsql security invoker set search_path='' as $$
begin
 if new.status in('active','pending') and exists(select 1 from public.planets a join public.planets b on b.id=new.planet_b where a.id=new.planet_a and a.resource=b.resource) then
  raise exception 'Le commerce exige deux ressources différentes.';
 end if;
 return new;
end $$;
revoke all on function private.trade_resource_compatibility() from public,anon,authenticated;
create trigger trade_resource_compatibility before insert or update on private.trade_links for each row execute function private.trade_resource_compatibility();

create or replace function private.trade_dashboard(p_planet_id uuid) returns jsonb language plpgsql security definer set search_path='' as $$
declare r jsonb;dest jsonb;links jsonb;reserved integer;v_civ integer;v_resource text;
begin
 r:=private.trade_dashboard_base(p_planet_id);
 select civilization,resource into v_civ,v_resource from public.planets where id=p_planet_id;
 select coalesce(jsonb_agg(d.value||jsonb_build_object('name',p.name,'civilization',p.civilization,'resource',p.resource,'available',greatest(0,p.trade_capacity-private.trade_used(p.id))) order by d.position),'[]'::jsonb)
 into dest from jsonb_array_elements(r->'destinations') with ordinality d(value,position) join public.planets p on p.id=(d.value->>'id')::uuid where p.resource<>v_resource;
 select coalesce(jsonb_agg(z.value||jsonb_build_object('name',p.name,'civilization',p.civilization,'resource',p.resource,'available',greatest(0,p.trade_capacity-private.trade_used(p.id)),
 'increase',case when i.id is null then null else jsonb_build_object('quantity',i.quantity,'expires_at',i.expires_at,'can_review',i.requester_planet<>p_planet_id) end) order by z.value->>'created_at' desc),'[]'::jsonb)
 into links from jsonb_array_elements(r->'links') z join public.planets p on p.id=(z.value->>'other_id')::uuid
 left join private.trade_increases i on i.link_id=(z.value->>'id')::uuid and i.status='pending' and i.expires_at>now() and z.value->>'status'='active';
 select coalesce(sum(i.quantity),0)::integer into reserved from private.trade_increases i join private.trade_links l on l.id=i.link_id where i.status='pending' and i.expires_at>now() and l.status='active' and(l.planet_a=p_planet_id or l.planet_b=p_planet_id);
 r:=jsonb_set(r,'{planet,reserved}',to_jsonb((r#>>'{planet,reserved}')::integer+reserved));
 r:=jsonb_set(r,'{planet,civilization}',to_jsonb(v_civ));
 r:=jsonb_set(r,'{planet,resource}',to_jsonb(v_resource));
 return r||jsonb_build_object('destinations',dest,'links',links);
end $$;

create function private.galaxy_map() returns jsonb language plpgsql security definer set search_path='' as $$
declare r jsonb;
begin
 -- The existing projection checks the connected participant and session.
 select coalesce(jsonb_agg(to_jsonb(s)||jsonb_build_object('appearance',p.race||'_'||p.resource) order by p.serial),'[]'::jsonb)
 into r from private.galaxy_signals() s join public.planets p on p.id=s.id;
 return r;
end $$;
revoke all on function private.galaxy_map() from public,anon;
grant execute on function private.galaxy_map() to authenticated;
create function public.galaxy_map() returns jsonb language sql security invoker set search_path='' as $$select private.galaxy_map();$$;
revoke all on function public.galaxy_map() from public,anon;
grant execute on function public.galaxy_map() to authenticated;
