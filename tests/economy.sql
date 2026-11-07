begin;
select set_config('qa.civil_before',(select md5(string_agg(to_jsonb(p)::text,'|' order by id)) from public.planets p where owner_empire_id is not null),true);
insert into auth.users(id,aud,role,email,email_confirmed_at,raw_app_meta_data,raw_user_meta_data) values
('00000000-0000-4000-8000-00000000ec11','authenticated','authenticated','economy-a@example.invalid',now(),'{"provider":"email"}','{}'),
('00000000-0000-4000-8000-00000000ec22','authenticated','authenticated','economy-b@example.invalid',now(),'{"provider":"email"}','{}');
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-00000000ec11',true);
select set_config('qa.ea',public.start_player('QA_Economy_A','QA Economie A')::text,true);
select set_config('qa.pa',(select id::text from public.planets),true);
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-00000000ec22',true);
select set_config('qa.eb',public.start_player('QA_Economy_B','QA Economie B')::text,true);
select set_config('qa.pb',(select id::text from public.planets),true);
reset role;
update public.planets set x=0,y=0,resource='aurite' where id=current_setting('qa.pa')::uuid;
update public.planets set x=500,y=0,resource='ferros' where id=current_setting('qa.pb')::uuid;
update private.economy_clock set enabled=true;
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-00000000ec11',true);
select set_config('qa.buy_id',gen_random_uuid()::text,true);
select public.trade_command('buy',current_setting('qa.pa')::uuid,null,5,null,current_setting('qa.buy_id')::uuid);
select public.trade_command('buy',current_setting('qa.pa')::uuid,null,5,null,current_setting('qa.buy_id')::uuid);
do $$ begin
 if (select trade_capacity from public.planets)<>5 then raise exception 'Duplicate purchase'; end if;
 if (select treasury from public.empires)<>98335 then raise exception 'Wrong purchase price or duplicate debit'; end if;
 begin perform public.trade_command('buy',current_setting('qa.pa')::uuid,null,6,null,current_setting('qa.buy_id')::uuid);raise exception 'Idempotency payload changed';
 exception when raise_exception then if sqlerrm not like 'Cet identifiant de commande%' then raise; end if;end;
 begin perform public.trade_command('buy',current_setting('qa.pa')::uuid,null,200,null,gen_random_uuid());raise exception 'Capacity limit bypass';
 exception when raise_exception then if sqlerrm not like 'La limite est de 200%' then raise; end if;end;
 begin perform 1 from private.economy_ledger;raise exception 'Ledger readable directly';
 exception when insufficient_privilege then null;end;
end $$;
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-00000000ec22',true);
select public.trade_command('buy',current_setting('qa.pb')::uuid,null,3,null,gen_random_uuid());
select public.set_planet_options(current_setting('qa.pb')::uuid,false,false);
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-00000000ec11',true);
select set_config('qa.link',(public.trade_command('propose',current_setting('qa.pa')::uuid,current_setting('qa.pb')::uuid,2,null,gen_random_uuid())->>'link_id'),true);
do $$
declare dash jsonb;
begin
 dash:=public.trade_dashboard(current_setting('qa.pa')::uuid);
 if (dash->'planet'->>'reserved')::int<>2 or (dash->'planet'->>'occupied')::int<>0 then raise exception 'Pending reservation wrong';end if;
 begin perform public.trade_command('propose',current_setting('qa.pa')::uuid,(select id from public.galaxy_signals() where id<>current_setting('qa.pa')::uuid and id<>current_setting('qa.pb')::uuid limit 1),4,null,gen_random_uuid());raise exception 'Reserved capacity reused';
 exception when raise_exception then if sqlerrm not like 'Capacités disponibles insuffisantes%' then raise;end if;end;
 if exists(select 1 from public.planets where id=current_setting('qa.pb')::uuid) then raise exception 'Other planet leaked';end if;
end $$;
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-00000000ec22',true);
select public.trade_command('accept',null,null,null,current_setting('qa.link')::uuid,gen_random_uuid());
select public.trade_command('accept',null,null,null,current_setting('qa.link')::uuid,gen_random_uuid());
reset role;
do $$ declare a record;b record;begin
 select * into a from private.planet_daily_rates(current_setting('qa.pa')::uuid);
 select * into b from private.planet_daily_rates(current_setting('qa.pb')::uuid);
 if a.trade-a.trade_cost<>2300 or b.trade-b.trade_cost<>2000 then raise exception 'Bilateral trade or local bonus wrong';end if;
 if a.civil<>23000 or b.civil<>20000 or a.military<>200 or a.fleet<>0 then raise exception 'Civil or unit upkeep wrong';end if;
end $$;
select set_config('qa.t0',(date_bin(interval '8 hours',now(),timestamptz '2000-01-01')-interval '16 hours')::text,true);
update public.planets set created_at=current_setting('qa.t0')::timestamptz where id in(current_setting('qa.pa')::uuid,current_setting('qa.pb')::uuid);
update private.economy_clock set activated_at=current_setting('qa.t0')::timestamptz,last_accrued_at=current_setting('qa.t0')::timestamptz,next_payout_at=current_setting('qa.t0')::timestamptz+interval '8 hours';
select private.economy_process(current_setting('qa.t0')::timestamptz+interval '4 hours');
do $$ begin
 if exists(select 1 from private.economy_ledger where empire_id=current_setting('qa.ea')::uuid) then raise exception 'Paid before cycle boundary';end if;
end $$;
select private.economy_process(current_setting('qa.t0')::timestamptz+interval '8 hours');
select private.economy_process(current_setting('qa.t0')::timestamptz+interval '8 hours');
do $$ begin
 if (select count(*) from private.economy_ledger where empire_id=current_setting('qa.ea')::uuid)<>1 then raise exception 'Duplicate payout';end if;
 if (select treasury from public.empires where id=current_setting('qa.ea')::uuid)<>98335+(select sum(net) from private.economy_ledger where empire_id=current_setting('qa.ea')::uuid) then raise exception 'Ledger treasury mismatch';end if;
end $$;
select private.economy_process(current_setting('qa.t0')::timestamptz+interval '16 hours');
do $$ begin
 if (select count(*) from private.economy_ledger where empire_id=current_setting('qa.ea')::uuid)<>2 then raise exception 'Offline catchup missed cycle';end if;
 if (select sum(military) from private.economy_ledger where empire_id=current_setting('qa.ea')::uuid)<>133 then raise exception 'Unit upkeep rounded or charged twice';end if;
end $$;
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-00000000ec11',true);
select public.trade_command('cancel',null,null,null,current_setting('qa.link')::uuid,gen_random_uuid());
reset role;
select set_config('qa.trade_accrued',(select (coalesce((select sum(trade) from private.economy_ledger where empire_id=current_setting('qa.ea')::uuid),0)+coalesce((select sum(trade) from private.economy_accruals where empire_id=current_setting('qa.ea')::uuid),0))::text),true);
select private.economy_process(now()+interval '8 hours');
do $$ begin
 if (select coalesce((select sum(trade) from private.economy_ledger where empire_id=current_setting('qa.ea')::uuid),0)+coalesce((select sum(trade) from private.economy_accruals where empire_id=current_setting('qa.ea')::uuid),0))<>current_setting('qa.trade_accrued')::numeric then raise exception 'Closed route still generated income';end if;
end $$;
set local role authenticated;
select set_config('qa.pending',(public.trade_command('propose',current_setting('qa.pa')::uuid,current_setting('qa.pb')::uuid,1,null,gen_random_uuid())->>'link_id'),true);
reset role;
select private.economy_process(now()+interval '25 hours');
do $$ begin
 if (select status from private.trade_links where id=current_setting('qa.pending')::uuid)<>'expired' then raise exception 'Pending request did not expire';end if;
 if private.trade_used(current_setting('qa.pb')::uuid)<>0 then raise exception 'Expired reservation retained capacity';end if;
 if has_function_privilege('authenticated','private.economy_process(timestamptz)','execute') then raise exception 'Client can choose payout clock';end if;
 if has_function_privilege('anon','public.trade_command(text,uuid,uuid,integer,uuid,uuid)','execute') then raise exception 'Anonymous economic action';end if;
end $$;
rollback;
select 'PASS: prices, purchase retries, capacity reservations, bilateral local bonuses, two scheduled payouts and offline catchup, no duplicate upkeep/payout, cancellation, expiry, privacy and server-only clock; fixtures rolled back' as result;
