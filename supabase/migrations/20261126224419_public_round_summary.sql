-- Intentionally public, read-only aggregates for the login screen.
-- No identity, account, military or planet-level information is exposed.
create function public.round_summary() returns jsonb language sql stable security definer set search_path='' as $$
 select jsonb_build_object('round',r.n,'starts_at',r.starts_at,'ends_at',r.ends_at,
 'players',(select count(distinct player_id) from public.empires where season_id=r.id),
 'planets',(select count(*) from public.planets where season_id=r.id and destroyed_at is null),
 'clans',(select count(*) from public.clans where season_id=r.id))
 from(select s.*,row_number() over(order by starts_at,id) n from public.seasons s)r where r.status='alpha';
$$;
revoke all on function public.round_summary() from public;
grant execute on function public.round_summary() to anon,authenticated;
