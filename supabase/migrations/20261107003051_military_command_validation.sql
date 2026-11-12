-- Reject missing captured-world names and stale factory quotes. Existing grants stay unchanged.
create or replace function private.military_command(p_action text,p_args jsonb,p_request_id uuid) returns jsonb language plpgsql security definer set search_path='' as $$
#variable_conflict use_column
declare e uuid;s uuid;p public.planets%rowtype;target public.planets%rowtype;f private.fleets%rowtype;prev private.military_commands%rowtype;g record;payload jsonb;r jsonb;pid uuid;fid uuid;kind text;q int;n int;ns int;nb int;nf int;delta int;remaining int;take_n int;cost bigint;hours numeric;distance numeric;v_id uuid;v_at timestamptz:=now();
begin
 select id into s from public.seasons where status='alpha' for update;e:=private.active_player_id();
 if p_request_id is null or p_args is null or jsonb_typeof(p_args)<>'object' then raise exception 'Commande invalide.';end if;
 payload:=jsonb_build_object('action',p_action,'args',p_args);select * into prev from private.military_commands where empire_id=e and request_id=p_request_id;
 if found then if prev.payload<>payload then raise exception 'Identifiant déjà utilisé pour une autre commande.';end if;return prev.result;end if;
 perform private.economy_process();
 pid:=(p_args->>'planet_id')::uuid;fid:=(p_args->>'fleet_id')::uuid;
 if p_action in ('recruitment','factory','ship','assemble','rename') then
 select * into p from public.planets where id=pid and owner_empire_id=e and season_id=s for update;if not found then raise exception 'Planète inaccessible.' using errcode='42501';end if;
 end if;
 if p_action in ('load','dispatch','disband') then
 select * into f from private.fleets where id=fid and empire_id=e and status='stationed' for update;if not found then raise exception 'Flotte indisponible.' using errcode='42501';end if;
 select * into p from public.planets where id=f.planet_id for update;
 end if;
 if p_action='recruitment' then
 if jsonb_typeof(p_args->'enabled') is distinct from 'boolean' then raise exception 'Choix de recrutement invalide.';end if;
 update public.planets set recruitment_enabled=(p_args->>'enabled')::boolean where id=p.id;
 elsif p_action='rename' then
 if p_args->>'name' is null or not p.rename_available or char_length(btrim(p_args->>'name')) not between 3 and 40 then raise exception 'Renommage indisponible ou nom invalide.';end if;
 update public.planets set name=btrim(p_args->>'name'),rename_available=false where id=p.id;
 elsif p_action in ('factory','ship') then
 if p_action='factory' then
  if p_args->>'expected_factories' is null or (p_args->>'expected_factories')::int<>p.factories then raise exception 'Le devis des usines a changé. Actualisez avant de confirmer.';end if;
  if p.factories>=200 or exists(select 1 from private.ship_jobs where planet_id=p.id and kind='factory' and completed_at is null and cancelled_at is null) then raise exception 'Un chantier d’usine est déjà en cours, ou la limite est atteinte.';end if;
  kind:='factory';q:=1;cost:=private.factory_price(p.factories+1);hours:=24*(1+.08*(p.factories-5));
 else
  kind:=p_args->>'kind';q:=(p_args->>'quantity')::int;
  if kind is null or kind not in ('scout','bomber','fighter') or q is null or q not between 1 and 200 then raise exception 'Production invalide.';end if;
  if q>p.factories-(select count(*) from private.ship_jobs where planet_id=p.id and kind<>'factory' and completed_at is null and cancelled_at is null) then raise exception 'Pas assez d’usines libres.';end if;
  cost:=(case kind when 'scout' then 2000 when 'bomber' then 12000 else 16000 end)*q;hours:=case kind when 'scout' then 2 when 'bomber' then 8 else 10 end;
 end if;
 if exists(select 1 from public.empires where id=e and (treasury<cost or maintenance_debt>0)) then raise exception 'Trésorerie insuffisante ou entretien à régulariser.';end if;
 update public.empires set treasury=treasury-cost where id=e;
 for n in 1..q loop insert into private.ship_jobs(empire_id,planet_id,kind,cost,started_at,finishes_at) values(e,p.id,kind,cost/q,v_at,v_at+make_interval(secs=>(hours*3600/(case when p.resource='ferros' then 1.15 else 1 end))::double precision)) returning id into v_id;end loop;
 elsif p_action='assemble' then
 ns:=(p_args->>'scouts')::int;nb:=(p_args->>'bombers')::int;nf:=(p_args->>'fighters')::int;
 if ns is null or nb is null or nf is null or least(ns,nb,nf)<0 or ns::bigint+nb+nf<1 or ns>p.scouts or nb>p.bombers or nf>p.fighters or char_length(btrim(p_args->>'name')) not between 1 and 40 or p_args->>'name' is null then raise exception 'Composition de flotte invalide.';end if;
 update public.planets set scouts=scouts-ns,bombers=bombers-nb,fighters=fighters-nf where id=p.id;
 insert into private.fleets(empire_id,season_id,name,race,supply_planet,planet_id,origin_id,scouts,bombers,fighters,created_at) values(e,s,btrim(p_args->>'name'),p.race,p.id,p.id,p.id,ns,nb,nf,v_at) returning id into v_id;
 elsif p_action='load' then
 q:=(p_args->>'soldiers')::int;if q is null or q<0 or q>10*(f.bombers+f.fighters) then raise exception 'Capacité de transport dépassée.';end if;
 delta:=q-f.soldiers;
 if delta<0 and f.lands_at is not null and v_at<f.lands_at then raise exception 'Le débarquement doit attendre une heure après l’arrivée.';end if;
 if delta>0 then
  remaining:=delta;
  if p.owner_empire_id=e then take_n:=least(p.soldiers,remaining);update public.planets set soldiers=soldiers-take_n where id=p.id;remaining:=remaining-take_n;end if;
  for g in select * from private.fleets where empire_id=e and planet_id=p.id and status='stationed' and ground_soldiers>0 order by id for update loop
   take_n:=least(g.ground_soldiers,remaining);update private.fleets set ground_soldiers=ground_soldiers-take_n where id=g.id;remaining:=remaining-take_n;exit when remaining=0;
  end loop;
  if remaining>0 then raise exception 'Soldats disponibles insuffisants.';end if;
 elsif delta<0 then
  if p.owner_empire_id=e then update public.planets set soldiers=soldiers-delta where id=p.id;
  else update private.fleets set ground_soldiers=ground_soldiers-delta where id=f.id;end if;
 end if;
 update private.fleets set soldiers=q where id=f.id;
 elsif p_action='dispatch' then
 select * into target from public.planets where id=(p_args->>'target_id')::uuid and season_id=s;
 if not found or target.id=p.id or f.scouts+f.bombers+f.fighters=0 or p_args->>'mission' is null or p_args->>'mission' not in ('attack','defend') or (target.owner_empire_id=e and p_args->>'mission'='attack') then raise exception 'Destination ou mission invalide.';end if;
 if f.ground_soldiers>0 then insert into private.fleets(empire_id,season_id,name,race,supply_planet,planet_id,origin_id,mission,ground_soldiers,created_at) values(e,s,left(f.name||' · garnison',40),f.race,f.supply_planet,p.id,p.id,f.mission,f.ground_soldiers,v_at);end if;
 distance:=sqrt(power(target.x-p.x,2)+power(target.y-p.y,2));
 update private.fleets set origin_id=p.id,destination_id=target.id,planet_id=null,status='transit',mission=p_args->>'mission',departed_at=v_at,arrives_at=v_at+make_interval(secs=>greatest(60,ceil(distance/sqrt(2000000)*691200))::double precision),lands_at=null,ground_soldiers=0 where id=f.id;
 elsif p_action='disband' then
 if p.owner_empire_id is distinct from e then raise exception 'Ralliez un monde sous votre contrôle pour dissoudre cette flotte.';end if;
 update public.planets set scouts=scouts+f.scouts,bombers=bombers+f.bombers,fighters=fighters+f.fighters,soldiers=soldiers+f.soldiers+f.ground_soldiers where id=p.id;
 update private.fleets set status='disbanded',scouts=0,bombers=0,fighters=0,soldiers=0,ground_soldiers=0 where id=f.id;
 else raise exception 'Action inconnue.';end if;
 r:=jsonb_build_object('ok',true,'id',coalesce(v_id,fid,pid));insert into private.military_commands values(e,p_request_id,payload,r);return r;
end $$;
