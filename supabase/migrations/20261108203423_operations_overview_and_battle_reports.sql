-- Combat-time side totals contain no player or fleet identifiers.
create function private.report_force_totals(p_snapshot jsonb,p_viewer uuid,p_side text,p_group text)
returns jsonb language sql immutable set search_path='' as $$
 select jsonb_build_object('scouts',coalesce(sum(scouts),0),'bombers',coalesce(sum(bombers),0),
 'fighters',coalesce(sum(fighters),0),'soldiers',coalesce(sum(ground::bigint+cargo),0),
 'ground',coalesce(sum(ground),0),'embarked',coalesce(sum(cargo),0))
 from jsonb_to_recordset(p_snapshot) x(empire_id uuid,side text,scouts int,bombers int,fighters int,ground int,cargo int)
 where case p_group when 'own' then side=p_side and empire_id=p_viewer
 when 'allies' then side=p_side and empire_id is distinct from p_viewer
 when 'enemies' then side<>p_side else false end;
$$;
revoke all on function private.report_force_totals(jsonb,uuid,text,text) from public,anon,authenticated;

create or replace function private.resolve_battle(p_planet uuid,p_at timestamptz) returns void language plpgsql set search_path='' as $$
#variable_conflict use_column
declare p public.planets%rowtype;snap jsonb;after_snap jsonb;sides jsonb;u record;t record;d private.battle_damage%rowtype;att record;def record;
 enemy record;sr numeric;gr numeric;ls integer;lb integer;lf integer;lg integer;ns integer;nb integer;nf integer;ng integer;nc integer;
 winner uuid;old_owner uuid;visible_ground boolean;my_before jsonb;my_after jsonb;enemy_space jsonb;enemy_ground jsonb;event_name text;fort numeric;
begin
 perform set_config('lw.development_at',p_at::text,true);
 select * into p from public.planets where id=p_planet for update;
 fort:=1+private.fortification(p,p_at);
 perform private.sync_planet_war(p.id,p_at);
 select jsonb_agg(to_jsonb(q)) into snap from(
 select p.id id,p.owner_empire_id empire_id,'defend'::text side,p.race,p.scouts,p.bombers,p.fighters,p.soldiers ground,0 cargo,true local,case when p.garrison_ready_at<=p_at then p.soldiers else 0 end ready
 union all select f.id,f.empire_id,f.mission,f.race,f.scouts,f.bombers,f.fighters,f.ground_soldiers,f.soldiers,false,case when f.ground_ready_at<=p_at then f.ground_soldiers else 0 end from private.fleets f where f.planet_id=p.id and f.status='stationed'
 ) q;
 select sum(scouts*2+bombers*10+fighters*12)::numeric hp,sum((scouts+fighters*8)*(case when race='vael' then 1.15 when race='khar' then .85 else 1 end))::numeric power,sum(ready)::numeric ground,sum(ready*(case when race='khar' then 1.15 when race='vael' then .85 else 1 end))::numeric ground_power,sum(bombers)::numeric bombers into att from jsonb_to_recordset(snap) as x(side text,race text,scouts int,bombers int,fighters int,ground int,ready int) where side='attack';
 select sum(scouts*2+bombers*10+fighters*12)::numeric hp,sum((scouts+fighters*8)*(case when race='vael' then 1.15 when race='khar' then .85 else 1 end))::numeric power,sum(ready)::numeric ground,sum(ready*(case when race='khar' then 1.15 when race='vael' then .85 else 1 end))::numeric ground_power,sum(bombers)::numeric bombers into def from jsonb_to_recordset(snap) as x(side text,race text,scouts int,bombers int,fighters int,ground int,ready int) where side='defend';
 if coalesce(att.hp,0)+coalesce((select sum(ground) from jsonb_to_recordset(snap) as z(side text,ground int) where side='attack'),0)=0 then return;end if;
 def.ground_power:=coalesce(def.ground_power,0)*fort;
 if coalesce(def.hp,0)+coalesce((select sum(ground) from jsonb_to_recordset(snap) as z(side text,ground int) where side='defend'),0)>0 then
 for u in select * from jsonb_to_recordset(snap) as x(id uuid,empire_id uuid,side text,race text,scouts int,bombers int,fighters int,ground int,cargo int,local boolean) loop
   if u.side='attack' then
     sr:=least(1,(coalesce(def.power,0)+coalesce(def.ground_power,0)*.1)*.12/greatest(coalesce(att.hp,0),1));
     gr:=least(1,(coalesce(def.ground_power,0)*.04+case when coalesce(def.power,0)>=3*coalesce(att.power,0) then coalesce(def.bombers,0)*2 else 0 end)/greatest((select sum(ground) from jsonb_to_recordset(snap) as z(side text,ground int) where side='attack'),1));
   else
     sr:=least(1,coalesce(att.power,0)*.12/greatest(coalesce(def.hp,0),1));
     gr:=least(1,((coalesce(att.ground_power,0)*.04+case when coalesce(att.power,0)>=3*coalesce(def.power,0) then coalesce(att.bombers,0)*2 else 0 end)/fort)/greatest((select sum(ground) from jsonb_to_recordset(snap) as z(side text,ground int) where side='defend'),1));
   end if;
   insert into private.battle_damage(planet_id,force_id) values(p.id,u.id) on conflict do nothing;
   select * into d from private.battle_damage where planet_id=p.id and force_id=u.id;
   ls:=least(u.scouts,floor(u.scouts*sr+d.scouts)::int);lb:=least(u.bombers,floor(u.bombers*sr+d.bombers)::int);lf:=least(u.fighters,floor(u.fighters*sr+d.fighters)::int);lg:=least(u.ground,floor(u.ground*gr+d.ground)::int);
   ns:=u.scouts-ls;nb:=u.bombers-lb;nf:=u.fighters-lf;ng:=u.ground-lg;
   nc:=least(10*(nb+nf),floor(u.cargo*(case when u.bombers+u.fighters=0 then 0 else (nb+nf)::numeric/(u.bombers+u.fighters) end))::int);
   update private.battle_damage set scouts=u.scouts*sr+d.scouts-ls,bombers=u.bombers*sr+d.bombers-lb,fighters=u.fighters*sr+d.fighters-lf,ground=u.ground*gr+d.ground-lg where planet_id=p.id and force_id=u.id;
   perform private.credit_battle_losses(snap,u.empire_id,u.side,ls::numeric*4+lb::numeric*24+lf::numeric*32+(u.cargo-nc),lg);
   if u.local then update public.planets set scouts=ns,bombers=nb,fighters=nf,soldiers=ng where id=p.id;
   else update private.fleets set scouts=ns,bombers=nb,fighters=nf,soldiers=nc,ground_soldiers=ng,status=case when ns+nb+nf+ng+nc=0 then 'destroyed' else status end where id=u.id;end if;
 end loop;
 end if;
 select * into p from public.planets where id=p.id;
 -- Record losses before capture transfers reserves or changes missions.
 select jsonb_agg(x.value||jsonb_build_object('scouts',case when (x.value->>'local')::boolean then p.scouts else coalesce(f.scouts,0) end,
 'bombers',case when (x.value->>'local')::boolean then p.bombers else coalesce(f.bombers,0) end,
 'fighters',case when (x.value->>'local')::boolean then p.fighters else coalesce(f.fighters,0) end,
 'ground',case when (x.value->>'local')::boolean then p.soldiers else coalesce(f.ground_soldiers,0) end,
 'cargo',case when (x.value->>'local')::boolean then 0 else coalesce(f.soldiers,0) end)) into after_snap
 from jsonb_array_elements(snap) x left join private.fleets f on f.id=(x.value->>'id')::uuid and not (x.value->>'local')::boolean;

 if (p.garrison_ready_at>p_at or p.soldiers=0) and not exists(select 1 from private.fleets where planet_id=p.id and status='stationed' and mission='defend' and ground_ready_at<=p_at and ground_soldiers>0) then
   select empire_id into winner from private.fleets where planet_id=p.id and status='stationed' and mission='attack' and ground_ready_at<=p_at and ground_soldiers>0 group by empire_id order by sum(ground_soldiers) desc,empire_id limit 1;
   if winner is not null and winner is distinct from p.owner_empire_id and (select count(*) from public.planets where owner_empire_id=winner)<12 then
     old_owner:=p.owner_empire_id;
     update public.planets set owner_empire_id=winner,rename_available=true,clan_tag_visible=false,recruitment_fraction=0 where id=p.id;

     update private.fleets set mission='defend' where planet_id=p.id and status='stationed' and mission='attack';
     perform private.sync_planet_war(p.id,p_at);
     event_name:='capture';
   else event_name:='battle';end if;
 else event_name:='battle';end if;
 perform private.sync_planet_war(p.id,p_at);
 for t in select distinct empire_id,side from jsonb_to_recordset(snap) as x(empire_id uuid,side text) where empire_id is not null loop
   select coalesce(sum(ground),0)>0,jsonb_build_object('scouts',coalesce(sum(scouts),0),'bombers',coalesce(sum(bombers),0),'fighters',coalesce(sum(fighters),0),'soldiers',coalesce(sum(ground+cargo),0)) into visible_ground,my_before from jsonb_to_recordset(snap) as x(empire_id uuid,scouts int,bombers int,fighters int,ground int,cargo int) where empire_id=t.empire_id;
   select jsonb_build_object('scouts',coalesce(sum(scouts),0),'bombers',coalesce(sum(bombers),0),'fighters',coalesce(sum(fighters),0)) into enemy_space from jsonb_to_recordset(snap) as x(side text,scouts int,bombers int,fighters int) where side<>t.side;
   enemy_ground:=null;if visible_ground then select to_jsonb(coalesce(sum(ground),0)) into enemy_ground from jsonb_to_recordset(snap) as x(side text,ground int) where side<>t.side;end if;
   select jsonb_object_agg(g,jsonb_build_object('before',private.report_force_totals(snap,t.empire_id,t.side,g),
   'after',private.report_force_totals(after_snap,t.empire_id,t.side,g))) into sides from unnest(array['own','allies','enemies']) g;
   my_before:=sides->'own'->'before';my_after:=sides->'own'->'after';
   insert into private.battle_reports(empire_id,planet_id,occurred_at,event,details) values(t.empire_id,p.id,p_at,event_name,jsonb_build_object('sides',sides,'mission',t.side,'before',my_before,'after',my_after,'enemy_space',enemy_space,'enemy_ground',enemy_ground,'captured',winner=t.empire_id and event_name='capture'));
 end loop;
end $$;

-- Fixed-size pagination uses the existing (empire_id,event_seq) index.
create function private.battle_reports_page(p_before bigint default null) returns jsonb
language plpgsql security definer set search_path='' as $$
declare e uuid;items jsonb;more boolean;
begin
 e:=private.active_player_id();
 with batch as (select r.* from private.battle_reports r where r.empire_id=e
 and r.event in('battle','capture','arrival','takeover') and (p_before is null or r.event_seq<p_before)
 order by r.event_seq desc limit 16),visible as(select * from batch order by event_seq desc limit 15)
 select coalesce((select jsonb_agg(jsonb_build_object('id',r.id,'cursor',r.event_seq::text,'planet_id',r.planet_id,
 'planet',private.military_label(r.planet_id,e),'appearance',p.race||'_'||p.resource,
 'occurred_at',r.occurred_at,'event',r.event,'details',r.details) order by r.event_seq desc)
 from visible r left join public.planets p on p.id=r.planet_id),'[]'::jsonb),(select count(*)>15 from batch) into items,more;
 return jsonb_build_object('items',items,'has_more',more,'next_before',case when more then items->-1->>'cursor' end);
end $$;
revoke all on function private.battle_reports_page(bigint) from public,anon,authenticated;
create function public.battle_reports_page(p_before bigint default null) returns jsonb
language sql security invoker set search_path='' as $$select private.battle_reports_page(p_before)$$;
revoke all on function public.battle_reports_page(bigint) from public,anon;
grant execute on function private.battle_reports_page(bigint),public.battle_reports_page(bigint) to authenticated;

alter function private.military_dashboard() rename to military_dashboard_locations;
revoke all on function private.military_dashboard_locations() from public,anon,authenticated;
create function private.military_dashboard() returns jsonb language plpgsql security definer set search_path='' as $$
declare e uuid;r jsonb;locations jsonb;recent jsonb;
begin
 e:=private.active_player_id();r:=private.military_dashboard_locations();
 select coalesce(jsonb_agg(x.value||case when p.owner_empire_id=e then jsonb_build_object('trade_capacity',p.trade_capacity,
 'trade_exploited',(select coalesce(sum(quantity),0) from private.trade_links l where l.status='active' and (l.source_planet=p.id or l.target_planet=p.id))) else '{}'::jsonb end order by x.ordinality),'[]'::jsonb)
 into locations from jsonb_array_elements(r->'locations') with ordinality x(value,ordinality) join public.planets p on p.id=(x.value->>'id')::uuid;
 select coalesce(jsonb_agg(jsonb_build_object('id',q.id,'planet',private.military_label(q.planet_id,e),'appearance',p.race||'_'||p.resource,
 'occurred_at',q.occurred_at,'event',q.event,'details',q.details) order by q.event_seq desc),'[]'::jsonb) into recent
 from (select * from private.battle_reports where empire_id=e and event in('battle','capture') order by event_seq desc limit 5)q
 left join public.planets p on p.id=q.planet_id;
 return r||jsonb_build_object('locations',locations,'report_page',private.battle_reports_page(),'recent_battles',recent);
end $$;
revoke all on function private.military_dashboard() from public,anon;
grant execute on function private.military_dashboard() to authenticated;
