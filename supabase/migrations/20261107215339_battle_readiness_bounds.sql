-- Bound cumulative capture unavailability to N/A 4.
create or replace function private.capture_military_state() returns trigger language plpgsql set search_path='' as $$
declare t timestamptz:=coalesce(nullif(current_setting('lw.development_at',true),'')::timestamptz,now());j record;hidden boolean;
begin
 if new.owner_empire_id is distinct from old.owner_empire_id then
  new.captured_at:=t;new.garrison_ready_at:=least(t+interval '4 hours',greatest(new.garrison_ready_at,t)+interval '1 hour');new.name:='Signal '||new.serial;new.rename_available:=true;new.clan_tag_visible:=false;
  if old.owner_empire_id is not null and old.scouts::bigint+old.bombers+old.fighters+old.soldiers>0 then
   insert into private.fleets(empire_id,season_id,name,race,supply_planet,planet_id,origin_id,mission,scouts,bombers,fighters,ground_soldiers,ground_ready_at) values(old.owner_empire_id,old.season_id,'Forces après conquête',old.race,old.id,old.id,old.id,'defend',old.scouts,old.bombers,old.fighters,old.soldiers,old.garrison_ready_at);
  end if;new.scouts:=0;new.bombers:=0;new.fighters:=0;new.soldiers:=0;
  if new.governance='tyrannie' then new.governance:='conseil';new.governance_changed_at:=t;end if;
  select coalesce(bool_or(camouflaged),false) into hidden from private.fleets where planet_id=new.id and empire_id=new.owner_empire_id and mission='attack' and ground_soldiers>0 and ground_ready_at<=t and status='stationed';
  new.anonymous_until:=case when hidden then t+interval '21 days' end;
  for j in update private.ship_jobs set cancelled_at=t where planet_id=new.id and completed_at is null and cancelled_at is null returning empire_id,cost loop update public.empires set treasury=treasury+j.cost where id=j.empire_id;end loop;
  update private.civilization_jobs set cancelled_at=t where planet_id=new.id and completed_at is null and cancelled_at is null;
  update private.fleets set mission=case mission when 'attack' then 'defend' else 'attack' end where destination_id=new.id and status='transit';
  update private.fleets set unavailable_until=least(t+interval '4 hours',greatest(unavailable_until,t)+interval '1 hour'),ground_ready_at=least(t+interval '4 hours',greatest(ground_ready_at,t)+interval '1 hour') where planet_id=new.id and status='stationed';
  if not hidden then insert into private.battle_reports(empire_id,planet_id,occurred_at,event,details) select distinct f.empire_id,new.id,t,'takeover',jsonb_build_object('new_owner',p.username) from private.fleets f join public.empires e on e.id=new.owner_empire_id join public.profiles p on p.id=e.player_id where f.planet_id=new.id and f.status='stationed' and f.scouts::bigint+f.bombers+f.fighters+f.soldiers+f.ground_soldiers>0;end if;
 end if;return new;
end $$;
