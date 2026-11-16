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

select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-00000000ec22',true);
select public.trade_command('buy',current_setting('qa.pb')::uuid,null,3,null,gen_random_uuid());
select public.set_planet_options(current_setting('qa.pb')::uuid,false,false);
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-00000000ec11',true);
select set_config('qa.link',(public.trade_command('propose',current_setting('qa.pa')::uuid,current_setting('qa.pb')::uuid,2,null,gen_random_uuid())->>'link_id'),true);

select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-00000000ec22',true);
select public.trade_command('accept',null,null,null,current_setting('qa.link')::uuid,gen_random_uuid());
select public.trade_command('accept',null,null,null,current_setting('qa.link')::uuid,gen_random_uuid());
reset role;

select set_config('qa.t0',(date_bin(interval '8 hours',now(),timestamptz '2000-01-01')-interval '16 hours')::text,true);
update public.planets set created_at=current_setting('qa.t0')::timestamptz where id in(current_setting('qa.pa')::uuid,current_setting('qa.pb')::uuid);
update private.economy_clock set activated_at=current_setting('qa.t0')::timestamptz,last_accrued_at=current_setting('qa.t0')::timestamptz,next_payout_at=current_setting('qa.t0')::timestamptz+interval '8 hours';
select private.economy_process(current_setting('qa.t0')::timestamptz+interval '4 hours');
do $$ begin if exists(select 1 from private.economy_ledger where empire_id=current_setting('qa.ea')::uuid) then raise exception 'Premature payout';end if;end $$;

select private.economy_process(current_setting('qa.t0')::timestamptz+interval '8 hours');
select private.economy_process(current_setting('qa.t0')::timestamptz+interval '8 hours');

select private.economy_process(current_setting('qa.t0')::timestamptz+interval '16 hours');
do $$ begin
 if (select count(*) from private.economy_ledger where empire_id=current_setting('qa.ea')::uuid)<>2 then raise exception 'Cycle count wrong';end if;
 if (select sum(military) from private.economy_ledger where empire_id=current_setting('qa.ea')::uuid)<>133 then raise exception 'Duplicate maintenance';end if;
end $$;

set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-00000000ec11',true);
select public.trade_command('cancel',null,null,null,current_setting('qa.link')::uuid,gen_random_uuid());
reset role;
select set_config('qa.trade_accrued',(select (coalesce((select sum(trade) from private.economy_ledger where empire_id=current_setting('qa.ea')::uuid),0)+coalesce((select sum(trade) from private.economy_accruals where empire_id=current_setting('qa.ea')::uuid),0))::text),true);
select private.economy_process(now()+interval '8 hours');
do $$ begin
 if (select coalesce((select sum(trade) from private.economy_ledger where empire_id=current_setting('qa.ea')::uuid),0)+coalesce((select sum(trade) from private.economy_accruals where empire_id=current_setting('qa.ea')::uuid),0))<>current_setting('qa.trade_accrued')::numeric then raise exception 'Income after route closed';end if;
end $$;

set local role authenticated;
select set_config('qa.pending',(public.trade_command('propose',current_setting('qa.pa')::uuid,current_setting('qa.pb')::uuid,1,null,gen_random_uuid())->>'link_id'),true);
reset role;
select private.economy_process(now()+interval '25 hours');

do $$ begin
 if (select count(*) from private.economy_ledger where empire_id=current_setting('qa.ea')::uuid)<3 then raise exception 'Catchup did not book multiple payouts';end if;
 if exists(select 1 from private.economy_ledger where empire_id=current_setting('qa.ea')::uuid group by payout_at having count(*)>1) then raise exception 'Duplicate payout';end if;
 if (select status from private.trade_links where id=current_setting('qa.pending')::uuid)<>'expired' then raise exception 'Pending did not expire';end if;
 if private.trade_used(current_setting('qa.pb')::uuid)<>0 then raise exception 'Expired capacity not released';end if;
 if (select treasury-maintenance_debt from public.empires where id=current_setting('qa.ea')::uuid)<>98335+(select sum(net) from private.economy_ledger where empire_id=current_setting('qa.ea')::uuid) then raise exception 'Cash ledger mismatch';end if;
end $$;
rollback;
select 'PASS: multiple real cycle boundaries, retries, catchup, cancellation, expiry and ledger conservation; all rolled back' as result;
