-- Canonical coordinates are projected at twice scale; trade economics stay unchanged.
create or replace function private.travel_seconds(d double precision) returns integer language sql immutable set search_path='' as $$select ceil((3600+least(sqrt(2000000),greatest(0,d))/sqrt(2000000)*601200)/2)::int$$;
-- Preserve current spatial position while halving remaining standard flight time.
update private.fleets set departed_at=now()-(now()-departed_at)/2,arrives_at=now()+(arrives_at-now())/2
where status='transit' and not gate_transit and departed_at<=now() and arrives_at>now();
