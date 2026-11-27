-- Compact the existing clusters into a 5 by 4 region; never split a cluster.
select private.economy_process();
lock table private.fleets,public.planets in share row exclusive mode;
create temporary table compact_flight_origins on commit drop as
select f.id,q.x*.375 x,q.y*.3 y from private.fleets f
cross join lateral private.fleet_position(f,now()) q
where f.status='transit' and f.arrives_at>now();

-- Fail before changing geography if this season cannot fit twenty clusters.
do $$begin
 if exists(select 1 from (select season_id,floor(x/150),floor(y/150)
 from public.planets where destroyed_at is null group by 1,2,3)s
 group by season_id having count(*)>20) then
 raise exception 'Plus de vingt clusters occupés : redistribution nécessaire';end if;
end $$;
with clusters as (
 select season_id,floor(x/150) cx,floor(y/150) cy,
 dense_rank() over(partition by season_id order by floor(y/150),floor(x/150))-1 r
 from public.planets where destroyed_at is null group by 1,2,3
)
update public.planets p set
 x=mod(c.r*7,20)%5*150+(p.x-c.cx*150),
 y=floor(mod(c.r*7,20)/5.0)*150+(p.y-c.cy*150)
from clusters c where p.season_id=c.season_id and p.destroyed_at is null
and floor(p.x/150)=c.cx and floor(p.y/150)=c.cy;

-- Retain arrival deadlines; only rebase the current origin and new destination.
update private.fleets f set route_x=q.x,route_y=q.y,departed_at=now()
from compact_flight_origins q where f.id=q.id;

create or replace function private.place_clustered_planet() returns trigger
language plpgsql set search_path='' as $$
declare cell record;
begin
 perform 1 from public.seasons where id=new.season_id for update;
 with cells as (
  select floor(x/50)::int cx,floor(y/50)::int cy,count(*) occupied
  from public.planets where season_id=new.season_id and destroyed_at is null group by 1,2
 ), clusters as (
  select floor(x/150)::int cx,floor(y/150)::int cy,count(*) population
  from public.planets where season_id=new.season_id and destroyed_at is null group by 1,2
 ), available as (
  select gx cx,gy cy,coalesce(c.occupied,0) occupied,coalesce(k.population,0) cluster_count
  from generate_series(0,14) gx cross join generate_series(0,11) gy
  left join cells c on c.cx=gx and c.cy=gy
  left join clusters k on k.cx=gx/3 and k.cy=gy/3
 ) select s.cx,s.cy,s.occupied into cell from available s
 where s.occupied<2 and s.cluster_count<15
 order by (s.cluster_count between 1 and 12) desc,(s.cluster_count between 13 and 14) desc,
 s.cluster_count desc,s.occupied,s.cy,s.cx limit 1;
 if not found then raise exception 'La carte galactique est pleine';end if;
 new.x:=cell.cx*50+case when cell.occupied=0 then 15 else 35 end;
 new.y:=cell.cy*50+case when cell.occupied=0 then 17 else 33 end;
 return new;
end $$;
revoke all on function private.place_clustered_planet() from public,anon,authenticated;
