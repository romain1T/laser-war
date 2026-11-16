create function private.planet_overview() returns jsonb language plpgsql security definer set search_path='' as $$
declare e uuid;s uuid;r jsonb;
begin
 select id into s from public.seasons where status='alpha' for update;e:=private.active_player_id();perform private.economy_process();
 select jsonb_build_object('prices',(select jsonb_object_agg(n::text,private.capacity_price(n)) from generate_series(1,200)n),
 'planets',coalesce((select jsonb_agg(jsonb_build_object('id',p.id,'capacity',p.trade_capacity,'used',private.trade_used(p.id),'available',greatest(0,p.trade_capacity-private.trade_used(p.id))) order by p.serial) from public.planets p where p.owner_empire_id=e),'[]'::jsonb)) into r;return r;
end $$;
create function private.set_governance(p_planet_id uuid,p_governance text,p_expected_governance text,p_request_id uuid) returns jsonb language plpgsql security definer set search_path='' as $$
declare e uuid;s uuid;p public.planets%rowtype;payload jsonb;prev private.military_commands%rowtype;r jsonb;
begin
 select id into s from public.seasons where status='alpha' for update;e:=private.active_player_id();
 if p_request_id is null or p_governance is null or p_governance not in ('conseil','tyrannie') then raise exception 'Choix politique invalide.';end if;
 payload:=jsonb_build_object('action','governance','planet',p_planet_id,'governance',p_governance,'expected',p_expected_governance);
 select * into prev from private.military_commands where empire_id=e and request_id=p_request_id;
 if found then if prev.payload<>payload then raise exception 'Identifiant déjà utilisé pour une autre commande.';end if;return prev.result;end if;
 perform private.economy_process();
 select * into p from public.planets where id=p_planet_id and owner_empire_id=e and season_id=s for update;
 if not found then raise exception 'Planète inaccessible.' using errcode='42501';end if;
 if p_expected_governance is null or p.governance<>p_expected_governance then raise exception 'La politique a changé. Actualisez avant de confirmer.';end if;
 update public.planets set governance=p_governance where id=p.id;
 r:=jsonb_build_object('ok',true,'governance',p_governance);insert into private.military_commands(empire_id,request_id,payload,result) values(e,p_request_id,payload,r);return r;
end $$;
create function public.planet_overview() returns jsonb language sql security invoker set search_path='' as $$select private.planet_overview();$$;
create function public.set_governance(p_planet_id uuid,p_governance text,p_expected_governance text,p_request_id uuid) returns jsonb language sql security invoker set search_path='' as $$select private.set_governance(p_planet_id,p_governance,p_expected_governance,p_request_id);$$;
revoke all on function private.planet_overview(),public.planet_overview(),private.set_governance(uuid,text,text,uuid),public.set_governance(uuid,text,text,uuid) from public,anon,authenticated;
grant execute on function private.planet_overview(),public.planet_overview(),private.set_governance(uuid,text,text,uuid),public.set_governance(uuid,text,text,uuid) to authenticated;
