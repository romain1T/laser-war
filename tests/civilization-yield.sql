begin;
insert into auth.users(id,aud,role,email,email_confirmed_at) values
('00000000-0000-4000-8000-00000000fa11','authenticated','authenticated','trade-resize-a@example.invalid',now()),
('00000000-0000-4000-8000-00000000fa22','authenticated','authenticated','trade-resize-b@example.invalid',now());
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-00000000fa11',true);
select public.start_player('QA_Resize_A','QA Resize Origine');
select set_config('qa.a',(select id::text from public.planets),true);
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-00000000fa22',true);
select public.start_player('QA_Resize_B','QA Resize Horizon');
select set_config('qa.b',(select id::text from public.planets),true);
reset role;
update public.planets set trade_capacity=10,resource=case when id=current_setting('qa.a')::uuid then 'aurite' else 'ferros' end where id in(current_setting('qa.a')::uuid,current_setting('qa.b')::uuid);
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-00000000fa11',true);
select set_config('qa.link',(public.trade_command('propose',current_setting('qa.a')::uuid,current_setting('qa.b')::uuid,2,null,gen_random_uuid())->>'link_id'),true);
reset role;
update public.planets set civilization=40,resource='aurite' where id=current_setting('qa.a')::uuid;
update public.planets set civilization=20,resource='ferros' where id=current_setting('qa.b')::uuid;
update private.trade_links set distance=500 where id=current_setting('qa.link')::uuid;
do $$ declare r record;begin
 select * into r from private.planet_daily_rates(current_setting('qa.a')::uuid);
 if r.trade-r.trade_cost<>6785 then raise exception 'Aurite/civilization trade mismatch';end if;
 select * into r from private.planet_daily_rates(current_setting('qa.b')::uuid);
 if r.trade-r.trade_cost<>3900 then raise exception 'Bilateral local civilization mismatch';end if;
 begin update public.planets set civilization=41 where id=current_setting('qa.a')::uuid;raise exception 'Civ 41 accepted';exception when check_violation then null;end;
end $$;
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-00000000fa11',true);
do $$ declare d jsonb;begin
 d:=public.trade_dashboard(current_setting('qa.a')::uuid);
 if (d#>>'{planet,civilization}')::int<>40 then raise exception 'Owned civ absent';end if;
 if (d#>>'{links,0,net_daily}')::numeric<>6785 then raise exception 'Forecast differs from accounting';end if;
 if (d#>>'{links,0,civilization}')::int<>20 then raise exception 'Partner civ absent';end if;
 if (d#>>'{links,0,available}')::int<>8 then raise exception 'Partner availability mismatch';end if;
 begin perform private.civilization_trade_multiplier(40);raise exception 'Private helper exposed';exception when insufficient_privilege then null;end;
end $$;
reset role;
rollback;
select 'PASS: local civilization and Aurite compose correctly, forecasts equal authoritative rates, civilization cap 40, partner availability and helper permissions' as result;
