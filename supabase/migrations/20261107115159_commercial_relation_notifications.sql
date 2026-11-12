-- Future transitions only; existing routes do not receive retroactive alerts.
create function private.notify_trade_relation() returns trigger language plpgsql security definer set search_path='' as $$
declare a public.planets%rowtype;b public.planets%rowtype;actor uuid;event_name text;recipient record;
begin
 if tg_op='UPDATE' and old.status=new.status then return new;end if;
 if new.status='active' then event_name:='trade_created';
 elsif tg_op='UPDATE' and old.status='active' and new.status='cancelled' then event_name:='trade_cancelled';
 else return new;end if;
 select * into a from public.planets where id=new.source_planet;
 select * into b from public.planets where id=new.target_planet;
 if a.owner_empire_id is null or b.owner_empire_id is null or a.owner_empire_id=b.owner_empire_id then return new;end if;
 select id into actor from public.empires where player_id=auth.uid() and season_id=new.season_id;
 if event_name='trade_cancelled' and (actor is null or actor not in(a.owner_empire_id,b.owner_empire_id)) then return new;end if;
 -- Scheduled acceptance is attributed to the receiving side.
 if event_name='trade_created' and (actor is null or actor not in(a.owner_empire_id,b.owner_empire_id)) then actor:=case when tg_op='INSERT' then a.owner_empire_id else b.owner_empire_id end;end if;
 for recipient in select a.owner_empire_id empire_id,a.id planet_id,b.name other_name union all select b.owner_empire_id,b.id,a.name loop
  if recipient.empire_id<>actor then
   insert into private.battle_reports(empire_id,planet_id,occurred_at,event,details)
   values(recipient.empire_id,recipient.planet_id,now(),event_name,jsonb_build_object('link_id',new.id,'other_planet',recipient.other_name,'quantity',new.quantity));
  end if;
 end loop;
 return new;
end $$;
revoke all on function private.notify_trade_relation() from public,anon,authenticated;
create trigger trade_relation_notification after insert or update of status on private.trade_links for each row execute function private.notify_trade_relation();
