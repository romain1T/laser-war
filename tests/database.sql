begin;
insert into auth.users(id,aud,role,email,email_confirmed_at,raw_app_meta_data,raw_user_meta_data)
values ('00000000-0000-4000-8000-0000000000a1','authenticated','authenticated','qa-alpha-a@example.invalid',now(),'{"provider":"email","providers":["email"]}','{}'),
('00000000-0000-4000-8000-0000000000b2','authenticated','authenticated','qa-alpha-b@example.invalid',now(),'{"provider":"email","providers":["email"]}','{}');
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-0000000000a1',true);
select public.found_empire('qa_alpha_a','Empire QA A','Monde QA A');
select public.found_empire('qa_alpha_a','Empire QA A','Monde QA A');
do $$
begin
 if (select count(*) from public.empires) <> 1 then raise exception 'Retry created duplicate empire'; end if;
 if (select count(*) from public.planets) <> 1 then raise exception 'Planet secrecy violated'; end if;
 if (select name from public.planets limit 1) <> 'Monde QA A' then raise exception 'Incorrect homeworld name'; end if;
 begin update public.empires set treasury=999999999; raise exception 'Direct treasury update allowed';
 exception when insufficient_privilege then null; end;
 begin insert into public.planets(season_id,race,resource) select id,'vael','aurite' from public.seasons; raise exception 'Direct planet creation allowed';
 exception when insufficient_privilege then null; end;
end $$;
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-0000000000b2',true);
do $$
begin
 if (select count(*) from public.empires) <> 0 or (select count(*) from public.planets) <> 0 or (select count(*) from public.profiles) <> 0 then raise exception 'Other player data leaked'; end if;
 begin perform public.found_empire('qa_alpha_a','Empire QA B','Monde QA B'); raise exception 'Duplicate username accepted';
 exception when raise_exception then
 if sqlerrm not like 'Ce pseudo est déjà utilisé%' then raise; end if; end;
end $$;
select public.found_empire('qa_alpha_b','Empire QA B','Monde QA B');
do $$
begin
 if (select count(*) from public.planets) <> 1 then raise exception 'Other homeworld leaked'; end if;
 if (select count(*) from public.empires) <> 1 then raise exception 'Other empire leaked'; end if;
 if (select treasury from public.empires limit 1) <> 100000 then raise exception 'Incorrect treasury'; end if;
end $$;
reset role;
do $$ begin
 if (select count(*) from public.planets) <> 60 then raise exception 'Incorrect universe expansion'; end if;
 if (select count(*) from public.empires) <> 2 then raise exception 'Incorrect empire count'; end if;
 if has_function_privilege('anon','public.found_empire(text,text,text)','execute') then raise exception 'Anonymous founding allowed'; end if;
end $$;
rollback;
select 'PASS: retries, username uniqueness, ownership RLS, server-only writes, universe growth; all test data rolled back' as result;
