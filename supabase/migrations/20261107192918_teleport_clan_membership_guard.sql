-- A missing membership is a denial, never a nullable permission.
create or replace function private.technology_command(p_action text,p_args jsonb,p_request_id uuid) returns jsonb language plpgsql security definer set search_path='' as $$
declare v_e uuid;v_s uuid;v_prev private.technology_commands%rowtype;v_payload jsonb;v_result jsonb;v_tech text;v_cost bigint;v_q int;v_p public.planets%rowtype;v_t public.planets%rowtype;v_origin uuid;v_target uuid;v_energy_planet uuid;v_foreign uuid;v_code text:=coalesce(p_args->>'password','');v_hash text;v_secret text;v_clan uuid;v_other_clan uuid;v_allowed boolean;v_remaining int;v_take int;v_group record;v_available bigint;v_has boolean;v_at timestamptz:=now();
begin
 select id into v_s from public.seasons where status='alpha' for update;v_e:=private.active_player_id();
 if p_request_id is null or p_args is null or jsonb_typeof(p_args)<>'object' then raise exception 'Commande invalide.';end if;
 if octet_length(v_code)>72 then raise exception 'Code limité à 72 octets.';end if;
 v_payload:=jsonb_build_object('action',p_action,'args',p_args-'password');
 select * into v_prev from private.technology_commands where empire_id=v_e and request_id=p_request_id;
 if found then
  if v_prev.payload<>v_payload or (v_prev.secret_hash is not null and extensions.crypt(v_code,v_prev.secret_hash)<>v_prev.secret_hash) or (v_prev.secret_hash is null and v_code<>'') then raise exception 'Identifiant déjà utilisé pour une autre commande.';end if;
  return v_prev.result;
 end if;
 perform private.economy_process();
 insert into private.player_technologies(empire_id) values(v_e) on conflict do nothing;
 if p_action='research' then
  v_tech:=p_args->>'technology';if v_tech not in('energy','teleport') or v_tech is null then raise exception 'Technologie inconnue.';end if;
  select case when v_tech='energy' then energy_unlocked_at is not null else teleport_unlocked_at is not null end into v_has from private.player_technologies where empire_id=v_e;
  v_cost:=case when v_has then 0 when v_tech='energy' then 150000 else 300000 end;
  if exists(select 1 from public.empires where id=v_e and (treasury<v_cost or maintenance_debt>0)) then raise exception 'Trésorerie insuffisante ou entretien à régulariser.';end if;
  if not v_has then
   update public.empires set treasury=treasury-v_cost where id=v_e;
   if v_tech='energy' then
    update private.player_technologies set energy_unlocked_at=v_at where empire_id=v_e;
    update public.planets set energy=greatest(energy,10),energy_fraction=0,development_last_at=v_at where owner_empire_id=v_e;
   else update private.player_technologies set teleport_unlocked_at=v_at where empire_id=v_e;end if;
  end if;
  v_result:=jsonb_build_object('ok',true,'technology',v_tech,'cost',v_cost);
 elsif p_action in('energy_capacity','password') then
  select * into v_p from public.planets where id=(p_args->>'planet_id')::uuid and owner_empire_id=v_e and season_id=v_s for update;
  if not found then raise exception 'Planète inaccessible.' using errcode='42501';end if;
  if p_action='energy_capacity' then
   if not exists(select 1 from private.player_technologies where empire_id=v_e and energy_unlocked_at is not null) then raise exception 'Recherchez la recharge d’énergie.';end if;
   v_q:=(p_args->>'quantity')::int;
   if v_q is null or v_q<1 or v_q>100-v_p.energy_max then raise exception 'Extension énergétique invalide.';end if;
   if (p_args->>'expected_capacity')::int is distinct from v_p.energy_max then raise exception 'Le devis énergétique a changé. Actualisez.';end if;
   select sum(private.energy_capacity_price(n)) into v_cost from generate_series(v_p.energy_max+1,v_p.energy_max+v_q)n;
   if exists(select 1 from public.empires where id=v_e and (treasury<v_cost or maintenance_debt>0)) then raise exception 'Trésorerie insuffisante ou entretien à régulariser.';end if;
   update public.empires set treasury=treasury-v_cost where id=v_e;
   update public.planets set energy_max=energy_max+v_q where id=v_p.id;
   v_result:=jsonb_build_object('ok',true,'cost',v_cost,'capacity',v_p.energy_max+v_q);
  else
   if not exists(select 1 from private.player_technologies where empire_id=v_e and teleport_unlocked_at is not null) then raise exception 'Recherchez la téléportation.';end if;
   if v_code='' then delete from private.planet_teleport_access where planet_id=v_p.id;
   else
    if char_length(v_code)<8 then raise exception 'Le code doit contenir au moins 8 caractères.';end if;
    v_secret:=extensions.crypt(v_code,extensions.gen_salt('bf',10));
    insert into private.planet_teleport_access(planet_id,password_hash) values(v_p.id,v_secret) on conflict(planet_id) do update set password_hash=excluded.password_hash,changed_at=v_at;
   end if;
   v_result:=jsonb_build_object('ok',true,'configured',v_code<>'');
  end if;
 elsif p_action='teleport' then
  v_origin:=(p_args->>'origin_id')::uuid;v_target:=(p_args->>'target_id')::uuid;v_q:=(p_args->>'quantity')::int;
  select * into v_p from public.planets where id=v_origin and season_id=v_s for update;
  select * into v_t from public.planets where id=v_target and season_id=v_s for update;
  if v_p.id is null or v_t.id is null or v_origin=v_target or v_p.owner_empire_id is null or v_t.owner_empire_id is null or (v_p.owner_empire_id<>v_e and v_t.owner_empire_id<>v_e) then raise exception 'Destination ou origine indisponible.';end if;
  if v_q is null or v_q<1 then raise exception 'Nombre de soldats invalide.';end if;
  if not exists(select 1 from private.player_technologies where empire_id=v_p.owner_empire_id and teleport_unlocked_at is not null) or not exists(select 1 from private.player_technologies where empire_id=v_t.owner_empire_id and teleport_unlocked_at is not null) then raise exception 'Les deux propriétaires doivent avoir débloqué la téléportation.';end if;
  if v_p.teleport_ready_at>v_at or v_t.teleport_ready_at>v_at then raise exception 'Connexion au réseau de téléportation en cours.';end if;
  v_energy_planet:=case when v_p.owner_empire_id=v_e then v_p.id else v_t.id end;
  if not exists(select 1 from private.player_technologies where empire_id=v_e and energy_unlocked_at is not null) then raise exception 'Recherchez la recharge d’énergie.';end if;
  v_cost:=case when v_p.owner_empire_id=v_e and v_t.owner_empire_id=v_e then (v_q::bigint+9)/10 else (v_q::bigint+4)/5 end;
  if (select energy from public.planets where id=v_energy_planet)<v_cost then raise exception 'Énergie disponible insuffisante.';end if;
  select coalesce(sum(ground_soldiers),0)+(case when v_p.owner_empire_id=v_e then v_p.soldiers else 0 end) into v_available from private.fleets where empire_id=v_e and planet_id=v_origin and status='stationed';
  if v_q>v_available then raise exception 'Soldats au sol disponibles insuffisants.';end if;
  v_foreign:=case when v_p.owner_empire_id<>v_e then v_p.id when v_t.owner_empire_id<>v_e then v_t.id else null end;
  if v_foreign is not null then
   select clan_id into v_clan from private.clan_memberships where empire_id=v_e;
   select clan_id into v_other_clan from private.clan_memberships where empire_id=case when v_p.owner_empire_id<>v_e then v_p.owner_empire_id else v_t.owner_empire_id end;
   v_allowed:=v_clan is not null and v_other_clan is not null and v_clan=v_other_clan;
   if not v_allowed then
    if (select count(*) from private.teleport_attempts where empire_id=v_e and attempted_at>clock_timestamp()-interval '1 minute')>=10 or (select count(*) from private.teleport_attempts where planet_id=v_foreign and attempted_at>clock_timestamp()-interval '1 minute')>=20 then return jsonb_build_object('ok',false,'error','Trop de tentatives. Réessayez dans une minute.');end if;
    insert into private.teleport_attempts(empire_id,planet_id) values(v_e,v_foreign);
    select password_hash into v_hash from private.planet_teleport_access where planet_id=v_foreign;
    if v_hash is null or v_code='' or extensions.crypt(v_code,v_hash)<>v_hash then return jsonb_build_object('ok',false,'error','Accès de téléportation refusé.');end if;
   end if;
  end if;
  update public.planets set energy=energy-v_cost where id=v_energy_planet;
  v_remaining:=v_q;
  if v_p.owner_empire_id=v_e then
   v_take:=least(v_p.soldiers,v_remaining);
   if v_take>0 then
    update public.planets set soldiers=soldiers-v_take where id=v_p.id;
    insert into private.fleets(empire_id,season_id,name,race,supply_planet,planet_id,origin_id,mission,ground_soldiers) values(v_e,v_s,'Renforts téléportés',v_p.race,v_energy_planet,v_t.id,v_p.id,'defend',v_take);
    v_remaining:=v_remaining-v_take;
   end if;
  end if;
  for v_group in select * from private.fleets where empire_id=v_e and planet_id=v_p.id and status='stationed' and ground_soldiers>0 order by id for update loop
   exit when v_remaining=0;v_take:=least(v_group.ground_soldiers,v_remaining);
   update private.fleets set ground_soldiers=ground_soldiers-v_take where id=v_group.id;
   insert into private.fleets(empire_id,season_id,name,race,supply_planet,planet_id,origin_id,mission,ground_soldiers) values(v_e,v_s,'Renforts téléportés',v_group.race,v_energy_planet,v_t.id,v_p.id,'defend',v_take);
   v_remaining:=v_remaining-v_take;
  end loop;
  if v_remaining<>0 then raise exception 'Soldats disponibles modifiés. Actualisez.';end if;
  update private.fleets set status='disbanded' where empire_id=v_e and planet_id=v_p.id and status='stationed' and scouts::bigint+bombers+fighters+soldiers+ground_soldiers=0;
  insert into private.battle_reports(empire_id,planet_id,occurred_at,event,details) values(v_e,v_t.id,v_at,'arrival',jsonb_build_object('fleet','Renforts téléportés','mission','defend','lands_at',v_at,'teleport',true,'soldiers',v_q));
  v_result:=jsonb_build_object('ok',true,'quantity',v_q,'energy_cost',v_cost);
 else raise exception 'Action technologique inconnue.';end if;
 if v_code<>'' and v_secret is null then v_secret:=extensions.crypt(v_code,extensions.gen_salt('bf',10));end if;
 insert into private.technology_commands(empire_id,request_id,payload,result,secret_hash) values(v_e,p_request_id,v_payload,v_result,v_secret);
 delete from private.teleport_attempts where attempted_at<clock_timestamp()-interval '1 day';
 return v_result;
end $$;
