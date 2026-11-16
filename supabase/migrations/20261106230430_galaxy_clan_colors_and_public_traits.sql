create function private.random_clan_color() returns text language sql volatile set search_path='' as $$
 with seed as materialized(select random()*2*pi() angle)
 select '#'||lpad(to_hex(round(160+80*cos(angle))::integer),2,'0')
 ||lpad(to_hex(round(160+80*cos(angle+2*pi()/3))::integer),2,'0')
 ||lpad(to_hex(round(160+80*cos(angle+4*pi()/3))::integer),2,'0') from seed;
$$;
revoke all on function private.random_clan_color() from public,anon,authenticated;
alter table public.clans add column color text not null default private.random_clan_color() check(color ~ '^#[0-9a-f]{6}$');

create or replace function private.galaxy_map() returns jsonb language plpgsql security definer set search_path='' as $$
declare r jsonb;
begin
 select coalesce(jsonb_agg(to_jsonb(s)||jsonb_build_object(
 'appearance',p.race||'_'||p.resource,'race',p.race,'resource',p.resource,'civilization',p.civilization,
 'clan_color',case when s.clan_name is not null then c.color else null end) order by p.serial),'[]'::jsonb)
 into r from private.galaxy_signals() s join public.planets p on p.id=s.id
 left join public.clans c on c.season_id=p.season_id and c.name=s.clan_name;
 return r;
end $$;
