create or replace function private.economy_process(p_now timestamptz default now())
returns void language plpgsql security definer set search_path='' as $$
declare v_id uuid; v_clock private.economy_clock%rowtype; v_end timestamptz;
 v_until timestamptz; v_cursor timestamptz; v_limit timestamptz;
begin
 for v_id in select season_id from private.economy_clock where enabled order by season_id loop
   perform 1 from public.seasons where id=v_id for update;
   select * into v_clock from private.economy_clock where season_id=v_id for update;
   select ends_at into v_end from public.seasons where id=v_id;
   v_limit:=least(p_now,v_end);v_cursor:=v_clock.last_accrued_at;
   if v_limit>v_cursor then
   loop
     v_until:=least(v_limit,v_clock.next_payout_at);
     insert into private.economy_accruals(empire_id,planet_id,season_id,civil,trade,trade_cost,military,fleet)
     select p.owner_empire_id,p.id,p.season_id,
       r.civil*d.seconds/86400,r.trade*d.seconds/86400,r.trade_cost*d.seconds/86400,r.military*d.seconds/86400,r.fleet*d.seconds/86400
     from public.planets p cross join lateral private.planet_daily_rates(p.id) r
     cross join lateral(select greatest(0,extract(epoch from(v_until-greatest(v_cursor,p.created_at)))) seconds) d
     where p.season_id=v_id and p.owner_empire_id is not null
     on conflict(empire_id,planet_id) do update set
       civil=private.economy_accruals.civil+excluded.civil,
       trade=private.economy_accruals.trade+excluded.trade,
       trade_cost=private.economy_accruals.trade_cost+excluded.trade_cost,
       military=private.economy_accruals.military+excluded.military,
       fleet=private.economy_accruals.fleet+excluded.fleet;
     if v_until=v_clock.next_payout_at or v_until=v_end then
       with booked as(
         insert into private.economy_ledger(empire_id,planet_id,payout_at,civil,trade,trade_cost,military,fleet,net)
         select empire_id,planet_id,v_until,floor(civil),floor(trade),floor(trade_cost),floor(military),floor(fleet),
           floor(civil)+floor(trade)-floor(trade_cost)-floor(military)-floor(fleet)
         from private.economy_accruals where season_id=v_id
         on conflict(empire_id,planet_id,payout_at) do nothing returning empire_id,net
       ),totals as(select empire_id,sum(net)::bigint net from booked group by empire_id)
       update public.empires e set
         treasury=greatest(0,e.treasury-e.maintenance_debt+t.net),
         maintenance_debt=greatest(0,-(e.treasury-e.maintenance_debt+t.net))
       from totals t where e.id=t.empire_id;
       update private.economy_accruals set civil=civil-floor(civil),trade=trade-floor(trade),
         trade_cost=trade_cost-floor(trade_cost),military=military-floor(military),fleet=fleet-floor(fleet)
       where season_id=v_id;
       v_clock.next_payout_at:=v_clock.next_payout_at+interval '8 hours';
     end if;
     v_cursor:=v_until;
     exit when v_cursor>=v_limit;
   end loop;
   update private.economy_clock set last_accrued_at=v_limit,next_payout_at=v_clock.next_payout_at where season_id=v_id;
   end if;
   -- Requests reserve both ends for at most 24 hours. No income while pending.
   update private.trade_links set status='expired',closed_at=p_now where season_id=v_id and status='pending' and expires_at<=p_now;
   -- Turning auto-accept back on also accepts existing unexpired incoming requests.
   update private.trade_links l set status='active',activated_at=p_now,expires_at=null
     from public.planets p where l.target_planet=p.id and p.auto_trade
       and l.season_id=v_id and l.status='pending' and l.expires_at>p_now;
 end loop;
end $$;

