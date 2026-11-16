begin;
insert into auth.users(id,aud,role,email,email_confirmed_at) values
('00000000-0000-4000-8000-00000000ab11','authenticated','authenticated','galaxy-map-a@example.invalid',now()),
('00000000-0000-4000-8000-00000000ab22','authenticated','authenticated','galaxy-map-b@example.invalid',now());
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-00000000ab11',true);
select public.start_player('QA_Map_A','QA Galaxie A');
select set_config('qa.map_a',(select id::text from public.planets),true);
select set_config('qa.map_clan',public.manage_clan('create',null,'QA Chromatique')::text,true);
select set_config('qa.map_color',(select color from public.clans where id=current_setting('qa.map_clan')::uuid),true);
select public.set_planet_options(current_setting('qa.map_a')::uuid,true,true);
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-00000000ab22',true);
select public.start_player('QA_Map_B','QA Galaxie B');
select set_config('qa.map_b',(select id::text from public.planets),true);
select public.manage_clan('join',current_setting('qa.map_clan')::uuid);
select public.set_planet_options(current_setting('qa.map_b')::uuid,true,true);
do $$ declare m jsonb;begin
 if current_setting('qa.map_color') !~ '^#[0-9a-f]{6}$' then raise exception 'Invalid random color';end if;
 m:=public.galaxy_map();
 if (select count(*) from jsonb_array_elements(m) x where x->>'clan_name'='QA Chromatique' and x->>'clan_color'=current_setting('qa.map_color'))<>2 then raise exception 'Clan worlds have different colors';end if;
 if exists(select 1 from jsonb_array_elements(m) x where not(x ?& array['race','resource','civilization']) or x ?| array['owner_empire_id','player_id','population','soldiers']) then raise exception 'Map projection incorrect';end if;
 if (select color from public.clans where id=current_setting('qa.map_clan')::uuid)<>current_setting('qa.map_color') then raise exception 'Color changed on read';end if;
 begin update public.clans set color='#ffffff' where id=current_setting('qa.map_clan')::uuid;raise exception 'Client changed color';exception when insufficient_privilege then null;end;
end $$;
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-00000000ab11',true);
select public.set_planet_options(current_setting('qa.map_a')::uuid,false,true);
reset role;
update public.planets set civilization=12 where id=current_setting('qa.map_a')::uuid;
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-00000000ab22',true);
do $$ declare s jsonb;begin
 select x into s from jsonb_array_elements(public.galaxy_map()) x where x->>'id'=current_setting('qa.map_a');
 if s->>'clan_name' is not null or s->>'clan_color' is not null then raise exception 'Undercover affiliation revealed';end if;
 if (s->>'civilization')::int<>12 then raise exception 'Untagged civilization absent';end if;
end $$;
reset role;
rollback;
select 'PASS: persistent random clan colors, identical tagged colors, hidden affiliation protected, public traits and civilization for untagged worlds, direct color writes denied; all rolled back' as result;
