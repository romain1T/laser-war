-- Fivefold space damage: two Khar scouts destroy one Vael scout in two
-- hourly rounds from a fresh battle. Ground pacing and stored fractions stay intact.
do $patch$
declare src text; updated text;
begin
 select pg_get_functiondef('private.resolve_battle(uuid,timestamptz)'::regprocedure) into src;
 updated:=replace(src,'*.12/greatest','*.60/greatest');
 if updated=src then raise exception 'Space damage expressions not found'; end if;
 execute updated;
end $patch$;
