-- Validated alpha economy. Initially disabled until verification and publication.
alter table public.empires add column maintenance_debt bigint not null default 0 check(maintenance_debt>=0);
create table private.economy_clock(
 season_id uuid primary key references public.seasons(id),
 enabled boolean not null default false,
 activated_at timestamptz not null default now(),
 last_accrued_at timestamptz not null default now(),
 next_payout_at timestamptz not null
);
insert into private.economy_clock(season_id,next_payout_at)
select id,date_bin(interval '8 hours',now(),timestamptz '2000-01-01 00:00:00+00')+interval '8 hours'
from public.seasons where status='alpha';

create table private.trade_links(
 id uuid primary key default gen_random_uuid(),
 season_id uuid not null references public.seasons(id),
 planet_a uuid not null references public.planets(id) on delete cascade,
 planet_b uuid not null references public.planets(id) on delete cascade,
 source_planet uuid not null references public.planets(id) on delete cascade,
 target_planet uuid not null references public.planets(id) on delete cascade,
 quantity integer not null check(quantity between 1 and 200),
 distance numeric(12,4) not null check(distance>=0),
 status text not null check(status in ('pending','active','declined','cancelled','expired')),
 created_at timestamptz not null default now(),
 expires_at timestamptz,
 activated_at timestamptz,
 closed_at timestamptz,
 check(planet_a<planet_b),
 check((source_planet=planet_a and target_planet=planet_b) or (source_planet=planet_b and target_planet=planet_a))
);
create unique index trade_one_open_pair on private.trade_links(planet_a,planet_b) where status in ('pending','active');
create index trade_links_a on private.trade_links(planet_a,status);
create index trade_links_b on private.trade_links(planet_b,status);
create index trade_links_source on private.trade_links(source_planet);
create index trade_links_target on private.trade_links(target_planet);
create index trade_links_season on private.trade_links(season_id);

create table private.economy_accruals(
 empire_id uuid not null references public.empires(id) on delete cascade,
 planet_id uuid not null references public.planets(id) on delete cascade,
 season_id uuid not null references public.seasons(id),
 civil numeric not null default 0,
 trade numeric not null default 0,
 trade_cost numeric not null default 0,
 military numeric not null default 0,
 fleet numeric not null default 0,
 primary key(empire_id,planet_id)
);
create index economy_accruals_planet on private.economy_accruals(planet_id);
create index economy_accruals_season on private.economy_accruals(season_id);
create table private.economy_ledger(
 id bigint generated always as identity primary key,
 empire_id uuid not null references public.empires(id) on delete cascade,
 planet_id uuid not null references public.planets(id) on delete cascade,
 payout_at timestamptz not null,
 civil bigint not null,
 trade bigint not null,
 trade_cost bigint not null,
 military bigint not null,
 fleet bigint not null,
 net bigint not null,
 unique(empire_id,planet_id,payout_at)
);
create index economy_ledger_planet on private.economy_ledger(planet_id);
create table private.economy_commands(
 empire_id uuid not null references public.empires(id) on delete cascade,
 request_id uuid not null,
 payload jsonb not null,
 result jsonb not null,
 created_at timestamptz not null default now(),
 primary key(empire_id,request_id)
);
alter table private.economy_clock enable row level security;
alter table private.trade_links enable row level security;
alter table private.economy_accruals enable row level security;
alter table private.economy_ledger enable row level security;
alter table private.economy_commands enable row level security;
revoke all on private.economy_clock,private.trade_links,private.economy_accruals,private.economy_ledger,private.economy_commands from public,anon,authenticated;

create function private.capacity_price(n integer) returns bigint language sql immutable strict set search_path='' as $$
 select case when n<1 or n>200 then null else round(1000*
 case when n<=20 then 1.0/3
 when n<=50 then 1.0/3+(15-1.0/3)*(3*power((n-20)/30.0,2)-2*power((n-20)/30.0,3))
 else 15+45*power((n-50)/150.0,1.3) end)::bigint end;
$$;
revoke all on function private.capacity_price(integer) from public,anon,authenticated;

create function private.planet_daily_rates(p_id uuid)
returns table(civil numeric,trade numeric,trade_cost numeric,military numeric,fleet numeric)
language sql stable set search_path='' as $$
 select p.population*.02*(case when p.resource='aurite' then 1.15 else 1 end),
 coalesce(t.gross,0)+(coalesce(t.gross,0)-coalesce(t.cost,0))*(case when p.resource='aurite' then .15 else 0 end),
 coalesce(t.cost,0),p.soldiers*2::numeric,(p.scouts::numeric*20+p.bombers::numeric*60+p.fighters::numeric*80)
 from public.planets p
 left join lateral(
 select sum(l.quantity*1500)::numeric gross,sum(l.quantity*least(l.distance,1000))::numeric cost
 from private.trade_links l where l.status='active' and (l.planet_a=p.id or l.planet_b=p.id)
 ) t on true where p.id=p_id;
$$;
revoke all on function private.planet_daily_rates(uuid) from public,anon,authenticated;

create function private.economy_process(p_now timestamptz default now())
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
       r.civil*d.days,r.trade*d.days,r.trade_cost*d.days,r.military*d.days,r.fleet*d.days
     from public.planets p cross join lateral private.planet_daily_rates(p.id) r
     cross join lateral(select greatest(0,extract(epoch from(v_until-greatest(v_cursor,p.created_at)))/86400) days) d
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
revoke all on function private.economy_process(timestamptz) from public,anon,authenticated;
create function private.trade_used(p_planet uuid) returns integer language sql stable set search_path='' as $$
 select coalesce(sum(quantity),0)::integer from private.trade_links
 where (planet_a=p_planet or planet_b=p_planet) and status in ('pending','active');
$$;
revoke all on function private.trade_used(uuid) from public,anon,authenticated;

create function private.trade_command(p_action text,p_planet_id uuid default null,p_target_id uuid default null,
 p_quantity integer default null,p_link_id uuid default null,p_request_id uuid default null)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_player uuid;v_season uuid;v_source public.planets%rowtype;v_target public.planets%rowtype;
 v_link private.trade_links%rowtype;v_payload jsonb;v_previous private.economy_commands%rowtype;
 v_result jsonb;v_cost bigint;v_cash bigint;v_debt bigint;v_status text;v_id uuid;
begin
 select id into v_season from public.seasons where status='alpha' for update;
 v_player:=private.active_player_id();
 if not exists(select 1 from private.economy_clock where season_id=v_season and enabled) then raise exception 'L’économie n’est pas encore activée.'; end if;
 if p_request_id is null then raise exception 'Identifiant de commande manquant.'; end if;
 v_payload:=jsonb_build_object('action',p_action,'planet',p_planet_id,'target',p_target_id,'quantity',p_quantity,'link',p_link_id);
 select * into v_previous from private.economy_commands where empire_id=v_player and request_id=p_request_id;
 if found then
   if v_previous.payload<>v_payload then raise exception 'Cet identifiant de commande a déjà été utilisé pour une autre action.'; end if;
   return v_previous.result;
 end if;
 perform private.economy_process();
 if p_action in ('buy','propose') then
   select * into v_source from public.planets where id=p_planet_id and owner_empire_id=v_player and season_id=v_season for update;
   if not found then raise exception 'Planète inaccessible.' using errcode='42501'; end if;
   if p_quantity is null or p_quantity<1 or p_quantity>200 then raise exception 'Quantité invalide.'; end if;
 end if;
 if p_action='buy' then
   if v_source.trade_capacity+p_quantity>200 then raise exception 'La limite est de 200 capacités par planète.'; end if;
   select sum(private.capacity_price(n)) into v_cost from generate_series(v_source.trade_capacity+1,v_source.trade_capacity+p_quantity) n;
   select treasury,maintenance_debt into v_cash,v_debt from public.empires where id=v_player for update;
   if v_debt>0 or v_cash<v_cost then raise exception 'Trésorerie insuffisante pour cet achat.'; end if;
   update public.empires set treasury=treasury-v_cost where id=v_player;
   update public.planets set trade_capacity=trade_capacity+p_quantity where id=v_source.id;
   v_result:=jsonb_build_object('status','purchased','cost',v_cost,'capacity',v_source.trade_capacity+p_quantity);
 elsif p_action='propose' then
   select * into v_target from public.planets where id=p_target_id and season_id=v_season for update;
   if not found or v_target.id=v_source.id then raise exception 'Destination invalide.'; end if;
   if exists(select 1 from private.trade_links where planet_a=least(v_source.id,v_target.id) and planet_b=greatest(v_source.id,v_target.id) and status in ('pending','active')) then
     raise exception 'Une liaison ou une demande existe déjà entre ces deux mondes.';
   end if;
   if v_source.trade_capacity-private.trade_used(v_source.id)<p_quantity then raise exception 'Capacités disponibles insuffisantes sur votre planète.'; end if;
   if v_target.trade_capacity-private.trade_used(v_target.id)<p_quantity then raise exception 'Cette liaison n’est pas disponible pour la quantité demandée.'; end if;
   v_status:=case when v_target.auto_trade or v_target.owner_empire_id=v_player then 'active' else 'pending' end;
   insert into private.trade_links(season_id,planet_a,planet_b,source_planet,target_planet,quantity,distance,status,expires_at,activated_at)
   values(v_season,least(v_source.id,v_target.id),greatest(v_source.id,v_target.id),v_source.id,v_target.id,p_quantity,
     round(sqrt(power(v_source.x-v_target.x,2)+power(v_source.y-v_target.y,2))::numeric,4),v_status,
     case when v_status='pending' then now()+interval '24 hours' end,case when v_status='active' then now() end)
   returning id into v_id;
   v_result:=jsonb_build_object('status',v_status,'link_id',v_id);
 elsif p_action in ('accept','decline','cancel') then
   select * into v_link from private.trade_links where id=p_link_id and season_id=v_season for update;
   if not found then raise exception 'Liaison inaccessible.' using errcode='42501'; end if;
   select * into v_source from public.planets where id=v_link.source_planet;
   select * into v_target from public.planets where id=v_link.target_planet;
   if p_action in ('accept','decline') then
     if v_target.owner_empire_id is distinct from v_player then raise exception 'Demande inaccessible.' using errcode='42501'; end if;
   elsif v_source.owner_empire_id is distinct from v_player and v_target.owner_empire_id is distinct from v_player then
     raise exception 'Liaison inaccessible.' using errcode='42501';
   end if;
   if p_action='accept' and v_link.status='pending' then
     update private.trade_links set status='active',activated_at=now(),expires_at=null where id=v_link.id;
     v_status:='active';
   elsif p_action='accept' and v_link.status='active' then v_status:='active';
   elsif p_action='decline' and v_link.status='pending' then
     update private.trade_links set status='declined',closed_at=now() where id=v_link.id;v_status:='declined';
   elsif p_action='decline' and v_link.status='declined' then v_status:='declined';
   elsif p_action='cancel' and v_link.status in ('pending','active') then
     update private.trade_links set status='cancelled',closed_at=now() where id=v_link.id;v_status:='cancelled';
   elsif p_action='cancel' and v_link.status='cancelled' then v_status:='cancelled';
   else raise exception 'Cette demande n’est plus disponible. Actualisez la page.';
   end if;
   v_result:=jsonb_build_object('status',v_status,'link_id',v_link.id);
 else raise exception 'Commande commerciale inconnue.';
 end if;
 insert into private.economy_commands(empire_id,request_id,payload,result) values(v_player,p_request_id,v_payload,v_result);
 return v_result;
end $$;
revoke all on function private.trade_command(text,uuid,uuid,integer,uuid,uuid) from public,anon;
grant execute on function private.trade_command(text,uuid,uuid,integer,uuid,uuid) to authenticated;
create function public.trade_command(p_action text,p_planet_id uuid default null,p_target_id uuid default null,
 p_quantity integer default null,p_link_id uuid default null,p_request_id uuid default null)
returns jsonb language sql security invoker set search_path='' as $$
 select private.trade_command(p_action,p_planet_id,p_target_id,p_quantity,p_link_id,p_request_id);
$$;
revoke all on function public.trade_command(text,uuid,uuid,integer,uuid,uuid) from public,anon;
grant execute on function public.trade_command(text,uuid,uuid,integer,uuid,uuid) to authenticated;

create function private.economy_overview() returns jsonb language plpgsql security definer set search_path='' as $$
declare v_player uuid:=private.active_player_id();v_season uuid;v_result jsonb;
begin
 select season_id into v_season from public.empires where id=v_player;
 perform 1 from public.seasons where id=v_season for update;
 perform private.economy_process();
 select jsonb_build_object('enabled',c.enabled,'activated_at',c.activated_at,'next_payout_at',c.next_payout_at,
 'treasury',e.treasury,'maintenance_debt',e.maintenance_debt,
 'planets',coalesce((select jsonb_agg(jsonb_build_object('id',p.id,'name',p.name,'civil',r.civil,'trade',r.trade,
 'trade_cost',r.trade_cost,'military',r.military,'fleet',r.fleet,
 'net',r.civil+r.trade-r.trade_cost-r.military-r.fleet) order by p.created_at)
 from public.planets p cross join lateral private.planet_daily_rates(p.id) r where p.owner_empire_id=v_player),'[]'::jsonb),
 'history',coalesce((select jsonb_agg(to_jsonb(h) order by h.payout_at desc) from(
 select payout_at,sum(civil) civil,sum(trade) trade,sum(trade_cost) trade_cost,sum(military) military,sum(fleet) fleet,sum(net) net
 from private.economy_ledger where empire_id=v_player group by payout_at order by payout_at desc limit 12) h),'[]'::jsonb))
 into v_result from public.empires e join private.economy_clock c on c.season_id=e.season_id where e.id=v_player;
 return v_result;
end $$;
revoke all on function private.economy_overview() from public,anon;
grant execute on function private.economy_overview() to authenticated;
create function public.economy_overview() returns jsonb language sql security invoker set search_path='' as $$select private.economy_overview();$$;
revoke all on function public.economy_overview() from public,anon;
grant execute on function public.economy_overview() to authenticated;

create function private.trade_dashboard(p_planet_id uuid) returns jsonb language plpgsql security definer set search_path='' as $$
declare v_player uuid:=private.active_player_id();v_planet public.planets%rowtype;v_bonus numeric;v_result jsonb;
begin
 select * into v_planet from public.planets where id=p_planet_id and owner_empire_id=v_player;
 if not found then raise exception 'Planète inaccessible.' using errcode='42501'; end if;
 perform 1 from public.seasons where id=v_planet.season_id for update;
 perform private.economy_process();
 -- Reload after settlement / automatic acceptance.
 select * into v_planet from public.planets where id=p_planet_id and owner_empire_id=v_player;
 v_bonus:=case when v_planet.resource='aurite' then 1.15 else 1 end;
 select jsonb_build_object('enabled',(select enabled from private.economy_clock where season_id=v_planet.season_id),
 'planet',jsonb_build_object('id',v_planet.id,'name',v_planet.name,'capacity',v_planet.trade_capacity,'auto_trade',v_planet.auto_trade,
 'occupied',coalesce((select sum(quantity) from private.trade_links where (planet_a=v_planet.id or planet_b=v_planet.id) and status='active'),0),
 'reserved',coalesce((select sum(quantity) from private.trade_links where (planet_a=v_planet.id or planet_b=v_planet.id) and status='pending'),0)),
 'prices',coalesce((select jsonb_agg(private.capacity_price(n) order by n) from generate_series(v_planet.trade_capacity+1,200) n),'[]'::jsonb),
 'destinations',coalesce((select jsonb_agg(jsonb_build_object('id',s.id,'name',s.designation,'clan_name',s.clan_name,'is_own',s.is_own,
 'distance',round(d.distance,2),'net_per_capacity',round((1500-least(d.distance,1000))*v_bonus,2),
 'distance_cost',round(least(d.distance,1000),2)) order by d.distance)
 from private.galaxy_signals() s cross join lateral(
 select round(sqrt(power(v_planet.x-s.x,2)+power(v_planet.y-s.y,2))::numeric,4) distance) d where s.id<>v_planet.id),'[]'::jsonb),
 'links',coalesce((select jsonb_agg(jsonb_build_object('id',l.id,'quantity',l.quantity,'status',l.status,'created_at',l.created_at,
 'expires_at',l.expires_at,'other_id',s.id,'name',s.designation,'clan_name',s.clan_name,'distance',round(l.distance,2),
 'net_daily',round(l.quantity*(1500-least(l.distance,1000))*v_bonus,2),
 'can_review',l.status='pending' and l.target_planet=v_planet.id) order by l.created_at desc)
 from private.trade_links l join private.galaxy_signals() s on s.id=case when l.planet_a=v_planet.id then l.planet_b else l.planet_a end
 where (l.planet_a=v_planet.id or l.planet_b=v_planet.id) and l.status in ('pending','active')),'[]'::jsonb))
 into v_result;
 return v_result;
end $$;
revoke all on function private.trade_dashboard(uuid) from public,anon;
grant execute on function private.trade_dashboard(uuid) to authenticated;
create function public.trade_dashboard(p_planet_id uuid) returns jsonb language sql security invoker set search_path='' as $$select private.trade_dashboard(p_planet_id);$$;
revoke all on function public.trade_dashboard(uuid) from public,anon;
grant execute on function public.trade_dashboard(uuid) to authenticated;

create extension if not exists pg_cron;
select cron.schedule('laser-war-economy','* * * * *','select private.economy_process();');
