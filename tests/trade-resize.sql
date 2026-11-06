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
select set_config('qa.cmd',gen_random_uuid()::text,true);
select public.resize_trade('increase',current_setting('qa.a')::uuid,current_setting('qa.link')::uuid,2,2,current_setting('qa.cmd')::uuid);
select public.resize_trade('increase',current_setting('qa.a')::uuid,current_setting('qa.link')::uuid,2,2,current_setting('qa.cmd')::uuid);
do $$ declare d jsonb;begin
 d:=public.trade_dashboard(current_setting('qa.a')::uuid);
 if (d#>>'{planet,occupied}')::int<>4 then raise exception 'Duplicate resize';end if;
 if not exists(select 1 from jsonb_array_elements(d->'destinations') x where x->>'name'='QA Resize Horizon' and (x->>'available')::int=6) then raise exception 'Destination name or availability';end if;
 begin perform public.resize_trade('increase',current_setting('qa.a')::uuid,current_setting('qa.link')::uuid,7,4,gen_random_uuid());raise exception 'Oversubscription accepted';exception when raise_exception then if sqlerrm not like 'Capacités disponibles insuffisantes%' then raise;end if;end;
end $$;
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-00000000fa22',true);
select public.set_planet_options(current_setting('qa.b')::uuid,false,false);
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-00000000fa11',true);
select public.resize_trade('increase',current_setting('qa.a')::uuid,current_setting('qa.link')::uuid,3,4,gen_random_uuid());
do $$ declare d jsonb;begin
 d:=public.trade_dashboard(current_setting('qa.a')::uuid);
 if (d#>>'{planet,occupied}')::int<>4 or (d#>>'{planet,reserved}')::int<>3 then raise exception 'Manual increase changed active quantity or failed reservation';end if;
end $$;
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-00000000fa22',true);
select public.resize_trade('accept',current_setting('qa.b')::uuid,current_setting('qa.link')::uuid,3,4,gen_random_uuid());
select public.resize_trade('decrease',current_setting('qa.b')::uuid,current_setting('qa.link')::uuid,2,7,gen_random_uuid());
do $$ declare d jsonb;begin
 d:=public.trade_dashboard(current_setting('qa.b')::uuid);
 if (d#>>'{planet,occupied}')::int<>5 or (d#>>'{planet,reserved}')::int<>0 then raise exception 'Accept or decrease wrong';end if;
 begin perform public.resize_trade('decrease',current_setting('qa.b')::uuid,current_setting('qa.link')::uuid,1,7,gen_random_uuid());raise exception 'Stale change accepted';exception when raise_exception then if sqlerrm not like 'La liaison a changé%' then raise;end if;end;
end $$;
select public.resize_trade('decrease',current_setting('qa.b')::uuid,current_setting('qa.link')::uuid,5,5,gen_random_uuid());
do $$ begin if (public.trade_dashboard(current_setting('qa.b')::uuid)#>>'{planet,occupied}')::int<>0 then raise exception 'Full removal did not release capacity';end if;end $$;
reset role;
rollback;
select 'PASS: automatic and manual increases, replay, availability, shared reservations, decrease, stale quote and closure; fixtures rolled back' as result;
