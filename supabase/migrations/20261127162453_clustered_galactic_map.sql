-- Settle accrued revenue using the previous geography before moving the worlds.
select private.economy_process();
lock table private.fleets,public.planets in share row exclusive mode;

-- Keep the remaining flight duration. Rebase the route from its current position
-- in the doubled coordinate system, towards the destination's new real position.
create temporary table galactic_flight_origins on commit drop as
select f.id,q.x*2 x,q.y*2 y from private.fleets f
cross join lateral private.fleet_position(f,now()) q
where f.status='transit' and f.arrives_at>now();

-- Canonical coordinates: 0..2000; 50 coordinate points = one distance unit.
-- Display coordinates are twice these values. Each cluster spans 150 points.
-- Balance existing worlds into ceil(n/13) clusters, then use nine distinct cells
-- before putting a second world in any cell. No world is created or deleted.
with ranked as (
 select id,season_id,row_number() over(partition by season_id order by y,x,serial)-1 r,
 count(*) over(partition by season_id) n from public.planets where destroyed_at is null
), grouped as (
 select *,greatest(1,ceil(n/13.0)::integer) k from ranked
), clustered as (
 select *,floor(r*k::numeric/n)::integer c from grouped
), slotted as (
 select *,row_number() over(partition by season_id,c order by r)-1 slot from clustered
), placed as (
 select *,mod(c*47,169) site,mod(slot*5,9) cell from slotted
)
update public.planets p set
 x=mod(t.site,13)*150+mod(t.cell,3)*50+case when slot<9 then 15 else 35 end,
 y=floor(t.site/13.0)*150+floor(t.cell/3.0)*50+case when slot<9 then 17 else 33 end
from placed t where p.id=t.id;

update private.fleets f set route_x=q.x,route_y=q.y,departed_at=now()
from galactic_flight_origins q where f.id=q.id;

-- New worlds use an available cell of an existing cluster first, with no more
-- than two worlds per cell. Existing planets never move again on registration.
create function private.place_clustered_planet() returns trigger
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
  from generate_series(0,38) gx cross join generate_series(0,38) gy
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
create trigger place_clustered_planet before insert on public.planets
for each row execute function private.place_clustered_planet();
