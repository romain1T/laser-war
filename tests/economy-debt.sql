begin;
insert into auth.users(id,aud,role,email,email_confirmed_at) values('00000000-0000-4000-8000-00000000ed33','authenticated','authenticated','debt-qa@example.invalid',now());
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-00000000ed33',true);
select set_config('qa.e',public.start_player('QA_Debt','QA Debt')::text,true);
select set_config('qa.p',(select id::text from public.planets),true);
reset role;
select set_config('qa.t',(date_bin(interval '8 hours',now(),timestamptz '2000-01-01')-interval '8 hours')::text,true);
update public.planets set created_at=current_setting('qa.t')::timestamptz,population=0,soldiers=6000,resource='ferros' where id=current_setting('qa.p')::uuid;
update public.empires set treasury=0 where id=current_setting('qa.e')::uuid;
update private.economy_clock set enabled=true,last_accrued_at=current_setting('qa.t')::timestamptz,next_payout_at=current_setting('qa.t')::timestamptz+interval '8 hours';
select private.economy_process(current_setting('qa.t')::timestamptz+interval '8 hours');
select private.economy_process(current_setting('qa.t')::timestamptz+interval '8 hours');
do $$ begin
 if (select maintenance_debt from public.empires where id=current_setting('qa.e')::uuid)<>4000 then raise exception 'Debt wrong or duplicated';end if;
 if (select treasury from public.empires where id=current_setting('qa.e')::uuid)<>0 then raise exception 'Negative treasury';end if;
end $$;
update public.planets set population=1000000,soldiers=0 where id=current_setting('qa.p')::uuid;
select private.economy_process(current_setting('qa.t')::timestamptz+interval '16 hours');
do $$ begin
 if (select maintenance_debt from public.empires where id=current_setting('qa.e')::uuid)<>0 then raise exception 'Debt not repaid first';end if;
 if (select treasury from public.empires where id=current_setting('qa.e')::uuid)<>2666 then raise exception 'Debt repayment balance wrong';end if;
end $$;
rollback;
select 'PASS: unpaid maintenance booked once, nonnegative cash and later income repays debt first; all rolled back' as result;
