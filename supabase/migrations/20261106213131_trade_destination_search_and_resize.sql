create table private.trade_increases(
 id uuid primary key default gen_random_uuid(),
 link_id uuid not null references private.trade_links(id) on delete cascade,
 requester_planet uuid not null references public.planets(id) on delete cascade,
 quantity integer not null check(quantity between 1 and 200),
 expires_at timestamptz not null default now()+interval '24 hours',
 status text not null default 'pending' check(status in('pending','accepted','declined','cancelled'))
);
create unique index trade_increases_one_pending on private.trade_increases(link_id) where status='pending';
create index trade_increases_link on private.trade_increases(link_id);
create index trade_increases_requester on private.trade_increases(requester_planet);
alter table private.trade_increases enable row level security;
revoke all on private.trade_increases from public,anon,authenticated;

create or replace function private.trade_used(p_planet uuid) returns integer language sql stable set search_path='' as $$
 select (coalesce((select sum(quantity) from private.trade_links where (planet_a=p_planet or planet_b=p_planet) and status in('pending','active')),0)
 +coalesce((select sum(i.quantity) from private.trade_increases i join private.trade_links l on l.id=i.link_id where i.status='pending' and i.expires_at>now() and l.status='active' and (l.planet_a=p_planet or l.planet_b=p_planet)),0))::integer;
$$;

create function private.resize_trade(p_action text,p_planet_id uuid,p_link_id uuid,p_quantity integer,p_expected_quantity integer,p_request_id uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_player uuid;v_season uuid;l private.trade_links%rowtype;i private.trade_increases%rowtype;
 a public.planets%rowtype;b public.planets%rowtype;payload jsonb;prev private.economy_commands%rowtype;result jsonb;
begin
 select id into v_season from public.seasons where status='alpha' for update;
 v_player:=private.active_player_id();
 if not exists(select 1 from private.economy_clock where season_id=v_season and enabled) then raise exception 'Économie désactivée.';end if;
 if p_request_id is null then raise exception 'Identifiant de commande manquant.';end if;
 payload:=jsonb_build_object('type','resize','action',p_action,'planet',p_planet_id,'link',p_link_id,'quantity',p_quantity,'expected',p_expected_quantity);
 select * into prev from private.economy_commands where empire_id=v_player and request_id=p_request_id;
 if found then if prev.payload<>payload then raise exception 'Cet identifiant de commande a déjà été utilisé.';end if;return prev.result;end if;
 perform private.economy_process();
 select * into a from public.planets where id=p_planet_id and owner_empire_id=v_player and season_id=v_season;
 if not found then raise exception 'Planète inaccessible.' using errcode='42501';end if;
 select * into l from private.trade_links where id=p_link_id and season_id=v_season and (planet_a=a.id or planet_b=a.id) for update;
 if not found then raise exception 'Liaison inaccessible.' using errcode='42501';end if;
 if l.status<>'active' then raise exception 'Cette liaison n’est plus active.';end if;
 if l.quantity is distinct from p_expected_quantity then raise exception 'La liaison a changé. Actualisez la page.';end if;
 select * into b from public.planets where id=case when l.planet_a=a.id then l.planet_b else l.planet_a end;
 update private.trade_increases set status='cancelled' where link_id=l.id and status='pending' and expires_at<=now();
 select * into i from private.trade_increases where link_id=l.id and status='pending' for update;
 if p_action='increase' then
  if i.id is not null then raise exception 'Une augmentation est déjà en attente.';end if;
  if p_quantity is null or p_quantity<1 or p_quantity>200-l.quantity then raise exception 'Quantité invalide.';end if;
  if a.trade_capacity-private.trade_used(a.id)<p_quantity or b.trade_capacity-private.trade_used(b.id)<p_quantity then raise exception 'Capacités disponibles insuffisantes.';end if;
  if b.auto_trade or b.owner_empire_id=v_player then
   update private.trade_links set quantity=quantity+p_quantity where id=l.id;
   result:=jsonb_build_object('status','active','quantity',l.quantity+p_quantity);
  else
   insert into private.trade_increases(link_id,requester_planet,quantity) values(l.id,a.id,p_quantity);
   result:=jsonb_build_object('status','pending_increase','quantity',l.quantity);
  end if;
 elsif p_action='decrease' then
  if p_quantity is null or p_quantity<1 or p_quantity>l.quantity then raise exception 'Quantité invalide.';end if;
  update private.trade_increases set status='cancelled' where link_id=l.id and status='pending';
  update private.trade_links set quantity=case when p_quantity=l.quantity then quantity else quantity-p_quantity end,
    status=case when p_quantity=l.quantity then 'cancelled' else status end,
    closed_at=case when p_quantity=l.quantity then now() else closed_at end where id=l.id;
  result:=jsonb_build_object('status',case when p_quantity=l.quantity then 'cancelled' else 'active' end,'quantity',l.quantity-p_quantity);
 elsif p_action in('accept','decline','withdraw') then
  if i.id is null or i.quantity is distinct from p_quantity then raise exception 'Cette demande n’est plus disponible.';end if;
  if (p_action='withdraw' and i.requester_planet<>a.id) or (p_action<>'withdraw' and i.requester_planet=a.id) then raise exception 'Demande inaccessible.' using errcode='42501';end if;
  update private.trade_increases set status=case p_action when 'accept' then 'accepted' when 'decline' then 'declined' else 'cancelled' end where id=i.id;
  if p_action='accept' then update private.trade_links set quantity=quantity+i.quantity where id=l.id;end if;
  result:=jsonb_build_object('status',case when p_action='accept' then 'active' else 'unchanged' end,'quantity',l.quantity+case when p_action='accept' then i.quantity else 0 end);
 else raise exception 'Commande inconnue.';end if;
 insert into private.economy_commands(empire_id,request_id,payload,result) values(v_player,p_request_id,payload,result);
 return result;
end $$;
revoke all on function private.resize_trade(text,uuid,uuid,integer,integer,uuid) from public,anon;
grant execute on function private.resize_trade(text,uuid,uuid,integer,integer,uuid) to authenticated;
create function public.resize_trade(p_action text,p_planet_id uuid,p_link_id uuid,p_quantity integer,p_expected_quantity integer,p_request_id uuid)
returns jsonb language sql security invoker set search_path='' as $$select private.resize_trade(p_action,p_planet_id,p_link_id,p_quantity,p_expected_quantity,p_request_id);$$;
revoke all on function public.resize_trade(text,uuid,uuid,integer,integer,uuid) from public,anon;
grant execute on function public.resize_trade(text,uuid,uuid,integer,integer,uuid) to authenticated;

alter function private.trade_dashboard(uuid) rename to trade_dashboard_base;
revoke all on function private.trade_dashboard_base(uuid) from public,anon,authenticated;
create function private.trade_dashboard(p_planet_id uuid) returns jsonb language plpgsql security definer set search_path='' as $$
declare r jsonb;dest jsonb;links jsonb;reserved integer;
begin
 r:=private.trade_dashboard_base(p_planet_id);
 select coalesce(jsonb_agg(d.value||jsonb_build_object('name',p.name,'available',greatest(0,p.trade_capacity-private.trade_used(p.id))) order by (d.value->>'distance')::numeric,p.id),'[]'::jsonb)
 into dest from jsonb_array_elements(r->'destinations') d join public.planets p on p.id=(d.value->>'id')::uuid;
 select coalesce(jsonb_agg(z.value||jsonb_build_object('name',p.name,'increase',case when i.id is null then null else jsonb_build_object('quantity',i.quantity,'expires_at',i.expires_at,'can_review',i.requester_planet<>p_planet_id) end) order by z.value->>'created_at' desc),'[]'::jsonb)
 into links from jsonb_array_elements(r->'links') z join public.planets p on p.id=(z.value->>'other_id')::uuid
 left join private.trade_increases i on i.link_id=(z.value->>'id')::uuid and i.status='pending' and i.expires_at>now() and z.value->>'status'='active';
 select coalesce(sum(i.quantity),0)::integer into reserved from private.trade_increases i join private.trade_links l on l.id=i.link_id where i.status='pending' and i.expires_at>now() and l.status='active' and (l.planet_a=p_planet_id or l.planet_b=p_planet_id);
 r:=jsonb_set(r,'{planet,reserved}',to_jsonb((r#>>'{planet,reserved}')::integer+reserved));
 return r||jsonb_build_object('destinations',dest,'links',links);
end $$;
revoke all on function private.trade_dashboard(uuid) from public,anon;
grant execute on function private.trade_dashboard(uuid) to authenticated;


create or replace function public.trade_dashboard(p_planet_id uuid) returns jsonb language sql security invoker set search_path='' as $$select private.trade_dashboard(p_planet_id);$$;
