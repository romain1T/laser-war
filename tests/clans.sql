begin;
select set_config('qa.worlds_before',(select count(*)::text from public.planets),true);
insert into auth.users(id,aud,role,email,email_confirmed_at,raw_app_meta_data,raw_user_meta_data)
values('00000000-0000-4000-8000-0000000000a1','authenticated','authenticated','qa-clan-a@example.invalid',now(),'{"provider":"email","providers":["email"]}','{}'),
('00000000-0000-4000-8000-0000000000b2','authenticated','authenticated','qa-clan-b@example.invalid',now(),'{"provider":"email","providers":["email"]}','{}'),
('00000000-0000-4000-8000-0000000000c3','authenticated','authenticated','qa-clan-c@example.invalid',now(),'{"provider":"email","providers":["email"]}','{}');
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-0000000000a1',true);
select public.start_player('qa_clan_a','QA Alpha');
select public.start_player('qa_clan_a','QA Alpha');
select set_config('qa.a_planet',(select id::text from public.planets),true);
select set_config('qa.clan',public.manage_clan('create',null,'QA Veilleurs')::text,true);
do $$ begin
 if (select count(*) from public.planets)<>1 then raise exception 'Duplicate founding or planet disclosure'; end if;
 if not (select auto_trade and not clan_tag_visible from public.planets limit 1) then raise exception 'Wrong option defaults'; end if;
 if public.my_clan()->>'role'<>'founder' then raise exception 'Missing founder role'; end if;
 if public.manage_clan('create',null,'QA Veilleurs')::text<>current_setting('qa.clan') then raise exception 'Create retry duplicated clan'; end if;
 begin perform 1 from private.clan_memberships; raise exception 'Memberships readable directly';
 exception when insufficient_privilege then null; end;
end $$;
select public.set_planet_options(current_setting('qa.a_planet')::uuid,true,false);
do $$ begin
 if (select name from public.planets limit 1)<>'QA Alpha' then raise exception 'Tag rewrote planet name'; end if;
 if (select auto_trade from public.planets limit 1) then raise exception 'Manual commerce preference not saved'; end if;
end $$;

select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-0000000000b2',true);
select public.start_player('qa_clan_b','QA Beta');
select set_config('qa.b_planet',(select id::text from public.planets),true);
do $$ begin
 if public.my_clan() is not null then raise exception 'Another membership leaked'; end if;
 if not exists(select 1 from public.galaxy_signals() where id=current_setting('qa.a_planet')::uuid and designation='QA Alpha' and clan_name='QA Veilleurs' and not is_own) then raise exception 'Public tag missing'; end if;
 if exists(select 1 from public.planets where id=current_setting('qa.a_planet')::uuid) then raise exception 'Other full planet disclosed'; end if;
 begin perform public.set_planet_options(current_setting('qa.a_planet')::uuid,false,true); raise exception 'Other player options writable';
 exception when insufficient_privilege then null; end;
 begin update public.planets set clan_tag_visible=true; raise exception 'Direct tag write allowed';
 exception when insufficient_privilege then null; end;
 begin perform public.manage_clan('create',null,'QA [Bad]'); raise exception 'Invalid brackets accepted';
 exception when raise_exception then if sqlerrm not like 'Le nom du clan doit%' then raise; end if; end;
end $$;
select public.manage_clan('join',current_setting('qa.clan')::uuid);
select public.manage_clan('join',current_setting('qa.clan')::uuid);
select public.set_planet_options(current_setting('qa.b_planet')::uuid,true,true);
do $$ begin
 if (public.my_clan()->>'member_count')::int<>2 then raise exception 'Duplicate clan join'; end if;
 if public.my_clan()->>'role'<>'member' then raise exception 'Join granted founder'; end if;
 begin perform public.manage_clan('create',null,'QA Second'); raise exception 'Second clan accepted';
 exception when raise_exception then if sqlerrm not like 'Vous appartenez déjà%' then raise; end if; end;
end $$;

select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-0000000000a1',true);
select public.set_planet_options(current_setting('qa.a_planet')::uuid,false,false);
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-0000000000b2',true);
do $$ begin
 if not exists(select 1 from public.galaxy_signals() where id=current_setting('qa.a_planet')::uuid and designation like 'Signal %' and clan_name is null and not is_own) then raise exception 'Hidden affiliation or name leaked'; end if;
end $$;
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-0000000000a1',true);
select public.manage_clan('leave',current_setting('qa.clan')::uuid);
select public.manage_clan('leave',current_setting('qa.clan')::uuid);
do $$ begin
 if public.my_clan() is not null then raise exception 'Membership not cleared'; end if;
 if (select clan_tag_visible from public.planets limit 1) then raise exception 'Leaving retained tag'; end if;
 begin perform public.set_planet_options(current_setting('qa.a_planet')::uuid,true,true); raise exception 'Tag accepted without clan';
 exception when raise_exception then if sqlerrm not like 'Rejoignez un clan%' then raise; end if; end;
end $$;
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-0000000000b2',true);
do $$ begin
 if public.my_clan()->>'role'<>'founder' then raise exception 'Founder not transferred'; end if;
end $$;

select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-0000000000c3',true);
select public.start_player('qa_clan_c','QA Gamma');
select set_config('qa.other_clan',public.manage_clan('create',null,'QA Nouvelle')::text,true);
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-0000000000a1',true);
select public.manage_clan('join',current_setting('qa.other_clan')::uuid);
do $$ begin
 if (select clan_tag_visible from public.planets limit 1) then raise exception 'New clan silently revealed affiliation'; end if;
 begin perform public.manage_clan('leave',current_setting('qa.clan')::uuid); raise exception 'Stale leave removed new clan';
 exception when raise_exception then if sqlerrm not like 'Votre clan a changé%' then raise; end if; end;
 if public.my_clan()->>'name'<>'QA Nouvelle' then raise exception 'New clan not retained'; end if;
end $$;
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-0000000000b2',true);
select public.manage_clan('leave',current_setting('qa.clan')::uuid);
do $$ begin
 if exists(select 1 from public.clans where id=current_setting('qa.clan')::uuid) then raise exception 'Empty clan not dissolved'; end if;
 if (select clan_tag_visible from public.planets limit 1) then raise exception 'Dissolved clan retained tag'; end if;
end $$;
reset role;
do $$ begin
 if (select count(*) from public.planets)<>current_setting('qa.worlds_before')::int+15 then raise exception 'Wrong world expansion'; end if;
 if has_function_privilege('anon','public.manage_clan(text,uuid,text)','execute') or has_function_privilege('anon','public.galaxy_signals()','execute') then raise exception 'Anonymous access granted'; end if;
end $$;
rollback;
select 'PASS: unnamed player start, defaults, clan create/join/leave and retries, founder succession, dissolution, opt-in visibility, cross-player access denial, stale command protection, all fixtures rolled back' as result;
