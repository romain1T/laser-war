-- Validated neutral-world rules; existing player worlds are not modified.
update public.planets set trade_capacity=5,soldiers=1,scouts=1,bombers=0,fighters=0,auto_trade=true,clan_tag_visible=false where owner_empire_id is null;

create function private.neutral_world_rules() returns trigger language plpgsql security invoker set search_path='' as $$
begin
 if new.owner_empire_id is null then
   if tg_op='INSERT' then
     new.trade_capacity:=5;new.soldiers:=1;new.scouts:=1;new.bombers:=0;new.fighters:=0;
     new.auto_trade:=true;new.clan_tag_visible:=false;
   elsif old.owner_empire_id is not null then
     new.trade_capacity:=5;new.soldiers:=1;new.scouts:=1;new.bombers:=0;new.fighters:=0;
     new.auto_trade:=true;new.clan_tag_visible:=false;
   elsif new.population is distinct from old.population or new.civilization is distinct from old.civilization then
     raise exception 'La population et la civilisation des planètes neutres restent fixes.';
   end if;
 end if;
 return new;
end $$;
revoke all on function private.neutral_world_rules() from public,anon,authenticated;
create trigger neutral_world_rules before insert or update on public.planets
 for each row execute function private.neutral_world_rules();
alter table public.planets add constraint neutral_trade_capacity_fixed
 check(owner_empire_id is not null or trade_capacity=5);
