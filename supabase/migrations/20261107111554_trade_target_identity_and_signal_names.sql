-- Normalize generated names only. Player-chosen planet names remain intact.
create function private.normalize_signal_name() returns trigger language plpgsql set search_path='' as $$
begin
 if new.name='Terra_Nullius_'||new.serial::text then new.name:='Signal '||new.serial::text;end if;return new;
end $$;
revoke all on function private.normalize_signal_name() from public,anon,authenticated;
create trigger normalize_signal_name before insert or update of name on public.planets for each row execute function private.normalize_signal_name();
update public.planets set name='Signal '||serial where name='Terra_Nullius_'||serial::text;

create or replace function private.trade_dashboard(p_planet_id uuid) returns jsonb language plpgsql security definer set search_path='' as $$
declare r jsonb;dest jsonb;links jsonb;reserved integer;v_civ integer;v_resource text;
begin
 r:=private.trade_dashboard_base(p_planet_id);
 select civilization,resource into v_civ,v_resource from public.planets where id=p_planet_id;
 select coalesce(jsonb_agg(d.value||jsonb_build_object('name',p.name,'civilization',p.civilization,'resource',p.resource,'available',greatest(0,p.trade_capacity-private.trade_used(p.id))) order by d.position),'[]'::jsonb)
 into dest from jsonb_array_elements(r->'destinations') with ordinality d(value,position) join public.planets p on p.id=(d.value->>'id')::uuid where p.resource<>v_resource;
 select coalesce(jsonb_agg(z.value||jsonb_build_object('name',p.name,'civilization',p.civilization,'resource',p.resource,'available',greatest(0,p.trade_capacity-private.trade_used(p.id)),
 'race',p.race,'population',p.population,'appearance',p.race||'_'||p.resource,
 'increase',case when i.id is null then null else jsonb_build_object('quantity',i.quantity,'expires_at',i.expires_at,'can_review',i.requester_planet<>p_planet_id) end) order by z.value->>'created_at' desc),'[]'::jsonb)
 into links from jsonb_array_elements(r->'links') z join public.planets p on p.id=(z.value->>'other_id')::uuid
 left join private.trade_increases i on i.link_id=(z.value->>'id')::uuid and i.status='pending' and i.expires_at>now() and z.value->>'status'='active';
 select coalesce(sum(i.quantity),0)::integer into reserved from private.trade_increases i join private.trade_links l on l.id=i.link_id where i.status='pending' and i.expires_at>now() and l.status='active' and(l.planet_a=p_planet_id or l.planet_b=p_planet_id);
 r:=jsonb_set(r,'{planet,reserved}',to_jsonb((r#>>'{planet,reserved}')::integer+reserved));
 r:=jsonb_set(r,'{planet,civilization}',to_jsonb(v_civ));
 r:=jsonb_set(r,'{planet,resource}',to_jsonb(v_resource));
 return r||jsonb_build_object('destinations',dest,'links',links);
end $$;

