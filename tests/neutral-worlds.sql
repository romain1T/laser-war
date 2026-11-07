begin;
insert into public.planets(season_id,name,race,resource,population,civilization,trade_capacity,soldiers,scouts)
select id,'QA Neutral Fixed','vael','aurite',1234567,3,0,100,0 from public.seasons where status='alpha';
do $$
declare p public.planets%rowtype;
begin
 select * into strict p from public.planets where name='QA Neutral Fixed';
 if p.trade_capacity<>5 or p.soldiers<>1 or p.scouts<>1 or p.bombers<>0 or p.fighters<>0 then raise exception 'Wrong neutral initialization'; end if;
 if not p.auto_trade or p.clan_tag_visible then raise exception 'Wrong neutral options'; end if;
 begin update public.planets set population=population+1 where id=p.id; raise exception 'Neutral population growth allowed';
 exception when raise_exception then if sqlerrm not like 'La population et la civilisation%' then raise; end if; end;
 begin update public.planets set civilization=civilization+1 where id=p.id; raise exception 'Neutral civilization growth allowed';
 exception when raise_exception then if sqlerrm not like 'La population et la civilisation%' then raise; end if; end;
 begin update public.planets set trade_capacity=6 where id=p.id; raise exception 'Neutral capacity growth allowed';
 exception when check_violation then null; end;
 if exists(select 1 from public.planets where owner_empire_id is null and (trade_capacity<>5 or soldiers<>1 or scouts<>1)) then raise exception 'Existing neutral worlds not initialized'; end if;
end $$;
rollback;
select 'PASS: existing/future neutral stats, five fixed capacities, population and civilization growth denied; fixture rolled back' as result;
