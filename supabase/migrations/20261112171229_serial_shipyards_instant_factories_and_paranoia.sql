-- New paranoia applies to already stationed outsiders, using arrival's clan rule.
create function private.enforce_stationed_paranoia() returns trigger language plpgsql set search_path='' as $$
begin
 if new.paranoid then
  update private.fleets set mission='attack',unavailable_until=greatest(unavailable_until,now()+interval '1 hour'),ground_ready_at=greatest(ground_ready_at,now()+interval '1 hour')
  where planet_id=new.id and status='stationed' and mission='defend' and empire_id is distinct from new.owner_empire_id and not private.same_clan(empire_id,new.owner_empire_id);
  perform private.sync_planet_war(new.id,now());
 end if;return new;
end $$;
revoke all on function private.enforce_stationed_paranoia() from public,anon,authenticated;
create trigger enforce_stationed_paranoia after update of paranoid on public.planets for each row execute function private.enforce_stationed_paranoia();

-- Finish already paid factory construction immediately, once; no extra debit.
with delivered as(update private.ship_jobs set completed_at=now() where kind='factory' and completed_at is null and cancelled_at is null returning planet_id)
update public.planets p set factories=least(200,factories+d.n) from(select planet_id,count(*)::int n from delivered group by planet_id)d where p.id=d.planet_id;

-- Convert existing parallel jobs to FIFO, retaining only unfinished work.
do $$declare p record;j record;cursor_at timestamptz;anchor_at timestamptz;work interval;begin
 for p in select distinct x.id,x.factories from public.planets x join private.ship_jobs sj on sj.planet_id=x.id where sj.completed_at is null and sj.cancelled_at is null loop
  cursor_at:=null;
  for j in select * from private.ship_jobs where planet_id=p.id and completed_at is null and cancelled_at is null order by started_at,finishes_at,id loop
   anchor_at:=coalesce(j.paused_at,now());cursor_at:=coalesce(cursor_at,anchor_at);
   work:=greatest(interval '0',j.finishes_at-greatest(j.started_at,anchor_at))*5/greatest(1,p.factories);
   update private.ship_jobs set started_at=cursor_at,finishes_at=cursor_at+work where id=j.id;
   cursor_at:=cursor_at+work;
  end loop;
 end loop;
end $$;

-- Runs after the stasis duration trigger: one paid unit per FIFO job.
create function private.queue_ship_job() returns trigger language plpgsql set search_path='' as $$
declare n int;tail timestamptz;begin
 if new.kind='factory' then return new;end if;
 select factories into n from public.planets where id=new.planet_id for update;
 if n<1 then raise exception 'Construisez une usine avant de produire.';end if;
 select max(finishes_at) into tail from private.ship_jobs where planet_id=new.planet_id and completed_at is null and cancelled_at is null;
 new.finishes_at:=greatest(new.started_at,coalesce(tail,new.started_at))+(new.finishes_at-new.started_at)*5/n;
 new.started_at:=greatest(new.started_at,coalesce(tail,new.started_at));return new;
end $$;
revoke all on function private.queue_ship_job() from public,anon,authenticated;
create trigger z_queue_ship_job before insert on private.ship_jobs for each row execute function private.queue_ship_job();

create function private.rescale_ship_queue() returns trigger language plpgsql set search_path='' as $$
declare t timestamptz:=coalesce(nullif(current_setting('lw.development_at',true),'')::timestamptz,now());begin
 if new.factories<>old.factories then
  update private.ship_jobs set started_at=coalesce(paused_at,t)+(started_at-coalesce(paused_at,t))*greatest(1,old.factories)/greatest(1,new.factories),
   finishes_at=coalesce(paused_at,t)+(finishes_at-coalesce(paused_at,t))*greatest(1,old.factories)/greatest(1,new.factories)
  where planet_id=new.id and kind<>'factory' and completed_at is null and cancelled_at is null;
 end if;perform private.sync_planet_war(new.id,t);return new;
end $$;
revoke all on function private.rescale_ship_queue() from public,anon,authenticated;
create trigger rescale_ship_queue after update of factories on public.planets for each row execute function private.rescale_ship_queue();

do $patch$declare src text;begin
 select pg_get_functiondef('private.military_command(text,jsonb,uuid)'::regprocedure) into src;
 src:=replace(src,'p.factories>=200 or exists(select 1 from private.ship_jobs where planet_id=p.id and kind=''factory'' and completed_at is null and cancelled_at is null)','p.factories>=200');
 src:=replace(src,'if q>p.factories-(select count(*) from private.ship_jobs where planet_id=p.id and kind<>''factory'' and completed_at is null and cancelled_at is null) then raise exception ''Pas assez d’usines libres.'';end if;','if p.factories<1 then raise exception ''Construisez une usine avant de produire.'';end if;');
 src:=replace(src,'for n in 1..q loop insert into private.ship_jobs','if kind=''factory'' then update public.planets set factories=factories+1 where id=p.id;else for n in 1..q loop insert into private.ship_jobs');
 src:=replace(src,'returning id into v_id;end loop;', 'returning id into v_id;end loop;end if;');
 execute src;
end $patch$;

-- Add exactly 35 normally initialized neutral worlds to the active alpha.
insert into public.planets(season_id,race,resource)
select s.id,(array['vael','khar','elys'])[1+((n-1)%3)],(array['aurite','biomasse','ferros'])[1+((n/3)%3)]
from public.seasons s cross join generate_series(1,35)n where s.status='alpha';
update public.planets set name='Signal '||serial where name is null;

-- Existing active paranoia is brought into the same rule now.
update public.planets set paranoid=paranoid where paranoid;
do $patch$declare src text;begin
 select pg_get_functiondef('private.sync_planet_war(uuid,timestamptz)'::regprocedure) into src;
 src:=replace(src,'if private.ground_superiority(pid,t) then','if private.ground_superiority(pid,t) or exists(select 1 from public.planets where id=pid and factories=0) then');execute src;
end $patch$;
