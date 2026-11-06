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
reset role;
update public.planets set resource='aurite' where id=current_setting('qa.b')::uuid;
set local role authenticated;
do $$ begin
 begin perform public.trade_command('propose',current_setting('qa.a')::uuid,current_setting('qa.b')::uuid,1,null,gen_random_uuid());raise exception 'Same resource accepted';
 exception when raise_exception then if sqlerrm not like 'Le commerce exige deux ressources%' then raise;end if;end;
 if exists(select 1 from jsonb_array_elements(public.trade_dashboard(current_setting('qa.a')::uuid)->'destinations') d where d->>'resource'='aurite') then raise exception 'Incompatible destination displayed';end if;
end $$;
reset role;
update public.planets set resource='ferros' where id=current_setting('qa.b')::uuid;
set local role authenticated;
select public.trade_command('propose',current_setting('qa.a')::uuid,current_setting('qa.b')::uuid,1,null,gen_random_uuid());
do $$ declare m jsonb;d jsonb;begin
 d:=public.trade_dashboard(current_setting('qa.a')::uuid);
 if not exists(select 1 from jsonb_array_elements(d->'destinations') x where x->>'id'=current_setting('qa.b') and x->>'resource'='ferros') then raise exception 'Compatible destination absent';end if;
 m:=public.galaxy_map();
 if not exists(select 1 from jsonb_array_elements(m) x where x->>'id'=current_setting('qa.b') and x->>'appearance' ~ '^(elys|vael|khar)_ferros$') then raise exception 'Planet art mapping missing';end if;
 if exists(select 1 from jsonb_array_elements(m) x where x ?| array['owner_empire_id','player_id','population','soldiers','scouts']) then raise exception 'Private data in map';end if;
end $$;
reset role;
do $$ begin if has_function_privilege('anon','public.galaxy_map()','execute') then raise exception 'Anonymous map access';end if;end $$;
rollback;
select 'PASS: incompatible resources rejected by server, compatible trade succeeds, destinations filtered, art keys public without owner/forces, anonymous access denied; all rolled back' as result;
