create function private.purchase_capacities(p_planet_id uuid,p_quantity integer,p_expected_capacity integer,p_request_id uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_player uuid;v_season uuid;v_current integer;v_exists boolean;
begin
 select id into v_season from public.seasons where status='alpha' for update;
 v_player:=private.active_player_id();
 select exists(select 1 from private.economy_commands where empire_id=v_player and request_id=p_request_id) into v_exists;
 if not v_exists then
   select trade_capacity into v_current from public.planets where id=p_planet_id and owner_empire_id=v_player;
   if not found then raise exception 'Planète inaccessible.' using errcode='42501'; end if;
   if p_expected_capacity is null or v_current<>p_expected_capacity then raise exception 'Le devis a changé. Actualisez la page avant de confirmer votre achat.'; end if;
 end if;
 return private.trade_command('buy',p_planet_id,null,p_quantity,null,p_request_id);
end $$;
revoke all on function private.purchase_capacities(uuid,integer,integer,uuid) from public,anon;
grant execute on function private.purchase_capacities(uuid,integer,integer,uuid) to authenticated;
create function public.purchase_capacities(p_planet_id uuid,p_quantity integer,p_expected_capacity integer,p_request_id uuid)
returns jsonb language sql security invoker set search_path='' as $$select private.purchase_capacities(p_planet_id,p_quantity,p_expected_capacity,p_request_id);$$;
revoke all on function public.purchase_capacities(uuid,integer,integer,uuid) from public,anon;
grant execute on function public.purchase_capacities(uuid,integer,integer,uuid) to authenticated;
