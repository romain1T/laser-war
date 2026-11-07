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
select public.purchase_capacities(current_setting('qa.pa')::uuid,5,0,current_setting('qa.buy_id')::uuid);
select public.purchase_capacities(current_setting('qa.pa')::uuid,5,0,current_setting('qa.buy_id')::uuid);
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
do $$ begin
 begin perform public.purchase_capacities(current_setting('qa.pa')::uuid,1,0,gen_random_uuid());raise exception 'Stale price accepted';
 exception when raise_exception then if sqlerrm not like 'Le devis a changé%' then raise;end if;end;
end $$;
reset role;
rollback;
select 'PASS: isolated fixture purchases, idempotency, unchanged payload and cap limit' as result;

