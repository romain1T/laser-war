-- Future foundations only: never rewrite an existing balance.
alter table public.empires alter column treasury set default 150000;
alter table public.profiles add column signature text not null default '' check(char_length(signature)<=280);
alter table public.planets add column governance_changed_at timestamptz;
-- Enforce the cooldown even for internal callers. Replays never update the row.
create function private.guard_governance() returns trigger language plpgsql set search_path='' as $$
begin
 if new.governance is distinct from old.governance then
  if old.governance_changed_at>now()-interval '72 hours' then raise exception 'Changement politique disponible le %.',old.governance_changed_at+interval '72 hours';end if;
  new.governance_changed_at:=now();
 end if;return new;
end $$;
revoke all on function private.guard_governance() from public,anon,authenticated;
create trigger governance_cooldown before update of governance on public.planets for each row execute function private.guard_governance();

create table private.forum_threads(
 id uuid primary key default gen_random_uuid(),season_id uuid not null references public.seasons(id),
 clan_id uuid references public.clans(id) on delete cascade,author_id uuid not null references public.empires(id) on delete cascade,
 title text not null check(char_length(title) between 3 and 120),created_at timestamptz not null default clock_timestamp());
create index forum_threads_scope on private.forum_threads(season_id,clan_id,created_at desc);
create table private.forum_posts(
 id bigint generated always as identity primary key,thread_id uuid not null references private.forum_threads(id) on delete cascade,
 author_id uuid not null references public.empires(id) on delete cascade,body text not null check(char_length(body) between 1 and 5000),created_at timestamptz not null default clock_timestamp());
create index forum_posts_thread on private.forum_posts(thread_id,id desc);
create index forum_posts_author on private.forum_posts(author_id,created_at desc);
create table private.conversations(
 id uuid primary key default gen_random_uuid(),season_id uuid not null references public.seasons(id),
 sender_id uuid not null references public.empires(id) on delete cascade,recipient_id uuid not null references public.empires(id) on delete cascade,
 planet_id uuid references public.planets(id) on delete set null,planet_label text,
 subject text not null check(char_length(subject) between 3 and 120),created_at timestamptz not null default clock_timestamp(),check(sender_id<>recipient_id));
create index conversations_sender on private.conversations(sender_id,created_at desc);
create index conversations_recipient on private.conversations(recipient_id,created_at desc);
create table private.messages(
 id bigint generated always as identity primary key,conversation_id uuid not null references private.conversations(id) on delete cascade,
 author_id uuid not null references public.empires(id) on delete cascade,body text not null check(char_length(body) between 1 and 5000),created_at timestamptz not null default clock_timestamp());
create index messages_conversation on private.messages(conversation_id,id desc);
create index messages_author on private.messages(author_id,created_at desc);
create table private.read_positions(empire_id uuid not null references public.empires(id) on delete cascade,channel text not null,cursor bigint not null default 0,primary key(empire_id,channel));
create table private.social_commands(empire_id uuid not null references public.empires(id) on delete cascade,request_id uuid not null,payload jsonb not null,result jsonb not null,primary key(empire_id,request_id));
alter table private.battle_reports add column event_seq bigint generated always as identity;
create unique index battle_reports_event_seq on private.battle_reports(event_seq);
create index battle_reports_empire_seq on private.battle_reports(empire_id,event_seq desc);
do $$declare n text;begin foreach n in array array['forum_threads','forum_posts','conversations','messages','read_positions','social_commands'] loop
 execute format('alter table private.%I enable row level security',n);execute format('revoke all on private.%I from public,anon,authenticated',n);
end loop;end $$;

-- Identity is public in explicit social interactions, never joined to planet ownership here.
create function private.social_author(p_empire uuid) returns jsonb language sql stable set search_path='' as $$
 select jsonb_build_object('username',p.username,'grade',e.grade,'avatar',p.avatar_path,'signature',p.signature)
 from public.empires e join public.profiles p on p.id=e.player_id where e.id=p_empire;
$$;
revoke all on function private.social_author(uuid) from public,anon,authenticated;
create function private.social_status() returns jsonb language plpgsql security definer set search_path='' as $$
declare e uuid;c uuid;r jsonb;begin
 e:=private.active_player_id();select clan_id into c from private.clan_memberships where empire_id=e;
 select jsonb_object_agg(channel,jsonb_build_object('latest',latest::text,'seen',seen::text,'unread',latest>seen)) into r from (
 select 'revenues' channel,coalesce((select max(id) from private.economy_ledger where empire_id=e),0) latest
 union all select 'alerts',coalesce((select max(event_seq) from private.battle_reports where empire_id=e),0)
 union all select 'forum:public',coalesce((select max(p.id) from private.forum_posts p join private.forum_threads t on t.id=p.thread_id where t.clan_id is null and t.season_id=(select season_id from public.empires where id=e)),0)
 union all select 'forum:clan',coalesce((select max(p.id) from private.forum_posts p join private.forum_threads t on t.id=p.thread_id where t.clan_id=c),0)
 union all select 'messages',coalesce((select max(m.id) from private.messages m join private.conversations v on v.id=m.conversation_id where (v.sender_id=e or v.recipient_id=e) and m.author_id<>e),0)
 ) x left join lateral(select coalesce((select cursor from private.read_positions where empire_id=e and channel=case when x.channel='forum:clan' then 'forum:'||c::text else x.channel end),0) seen) y on true;
 r:=jsonb_set(r,'{forum:public,unread}',to_jsonb(exists(select 1 from private.forum_posts p join private.forum_threads t on t.id=p.thread_id where t.clan_id is null and t.season_id=(select season_id from public.empires where id=e) and p.id>greatest((r->'forum:public'->>'seen')::bigint,coalesce((select cursor from private.read_positions where empire_id=e and channel='thread:'||t.id),0)))));
 r:=jsonb_set(r,'{forum:clan,unread}',to_jsonb(exists(select 1 from private.forum_posts p join private.forum_threads t on t.id=p.thread_id where t.clan_id=c and p.id>greatest((r->'forum:clan'->>'seen')::bigint,coalesce((select cursor from private.read_positions where empire_id=e and channel='thread:'||t.id),0)))));
 r:=jsonb_set(r,'{messages,unread}',to_jsonb(exists(select 1 from private.messages m join private.conversations v on v.id=m.conversation_id where (v.sender_id=e or v.recipient_id=e) and m.author_id<>e and m.id>coalesce((select cursor from private.read_positions where empire_id=e and channel='conversation:'||v.id),0))));
 return r||jsonb_build_object('revenue_dates',coalesce((select jsonb_agg(distinct payout_at) from private.economy_ledger where empire_id=e and id>(r->'revenues'->>'seen')::bigint),'[]'),'alert_ids',coalesce((select jsonb_agg(id) from private.battle_reports where empire_id=e and event_seq>(r->'alerts'->>'seen')::bigint),'[]'));
end $$;

-- Read acknowledgements are bounded by an actually returned snapshot, never the future.
create function private.social_read(p_channel text,p_cursor bigint) returns void language plpgsql security definer set search_path='' as $$
declare e uuid;c uuid;maximum bigint;k text;begin
 e:=private.active_player_id();
 if p_channel in ('revenues','alerts','forum:public') then
  maximum:=((private.social_status())->p_channel->>'latest')::bigint;k:=p_channel;
 elsif p_channel='forum:clan' then
  select clan_id into c from private.clan_memberships where empire_id=e;if c is null then raise exception 'Clan inaccessible.' using errcode='42501';end if;
  maximum:=((private.social_status())->p_channel->>'latest')::bigint;k:='forum:'||c::text;
 elsif p_channel like 'thread:%' then
  select max(p.id) into maximum from private.forum_posts p join private.forum_threads t on t.id=p.thread_id where t.id=substring(p_channel from 8)::uuid and t.season_id=(select season_id from public.empires where id=e) and (t.clan_id is null or exists(select 1 from private.clan_memberships where empire_id=e and clan_id=t.clan_id));k:=p_channel;
 elsif p_channel like 'conversation:%' then
  select max(m.id) into maximum from private.messages m join private.conversations v on v.id=m.conversation_id where v.id=substring(p_channel from 14)::uuid and (v.sender_id=e or v.recipient_id=e);k:=p_channel;
 else raise exception 'Canal inaccessible.' using errcode='42501';end if;
 if maximum is null or p_cursor is null or p_cursor<0 or p_cursor>maximum then raise exception 'Lecture invalide.';end if;
 insert into private.read_positions(empire_id,channel,cursor) values(e,k,p_cursor) on conflict(empire_id,channel) do update set cursor=greatest(private.read_positions.cursor,excluded.cursor);
end $$;

create function private.social_feed(p_scope text default 'public',p_thread_id uuid default null,p_conversation_id uuid default null,p_before bigint default null) returns jsonb language plpgsql security definer set search_path='' as $$
declare e uuid;s uuid;c uuid;t private.forum_threads%rowtype;v private.conversations%rowtype;r jsonb;posts jsonb;msgs jsonb;begin
 e:=private.active_player_id();select season_id into s from public.empires where id=e;
 if p_scope not in ('public','clan') or p_scope is null then raise exception 'Forum invalide.';end if;
 if p_scope='clan' then select clan_id into c from private.clan_memberships where empire_id=e;if c is null then raise exception 'Clan inaccessible.' using errcode='42501';end if;end if;
 if p_thread_id is not null then
  select * into t from private.forum_threads where id=p_thread_id and season_id=s and clan_id is not distinct from c;
  if not found then raise exception 'Discussion inaccessible.' using errcode='42501';end if;
  select coalesce(jsonb_agg(to_jsonb(x) order by x.id::bigint),'[]') into posts from(select p.id::text id,p.body,p.created_at,private.social_author(p.author_id) author,p.id>coalesce((select cursor from private.read_positions where empire_id=e and channel='thread:'||t.id),0) unread from private.forum_posts p where thread_id=t.id and (p_before is null or p.id<p_before) order by p.id desc limit 50)x;
 end if;
 if p_conversation_id is not null then
  select * into v from private.conversations where id=p_conversation_id and season_id=s and (sender_id=e or recipient_id=e);
  if not found then raise exception 'Conversation inaccessible.' using errcode='42501';end if;
  select coalesce(jsonb_agg(to_jsonb(x) order by x.id::bigint),'[]') into msgs from(select m.id::text id,m.body,m.created_at,m.author_id=e mine,
   case when v.planet_label is not null and m.author_id=v.recipient_id and e=v.sender_id then jsonb_build_object('username',v.planet_label,'grade','','avatar',null,'signature','') else private.social_author(m.author_id) end author,
   m.author_id<>e and m.id>coalesce((select cursor from private.read_positions where empire_id=e and channel='conversation:'||v.id),0) unread
   from private.messages m where conversation_id=v.id and (p_before is null or m.id<p_before) order by m.id desc limit 50)x;
 end if;
 select jsonb_build_object('status',private.social_status(),'scope',p_scope,'thread',case when t.id is not null then jsonb_build_object('id',t.id,'title',t.title) end,'posts',coalesce(posts,'[]'),
 'threads',coalesce((select jsonb_agg(to_jsonb(x) order by x.latest::bigint desc) from(select ft.id,ft.title,private.social_author(ft.author_id) author,count(p.id) count,max(p.id)::text latest,max(p.created_at) updated_at,max(p.id)>greatest(coalesce((select cursor from private.read_positions where empire_id=e and channel='thread:'||ft.id),0),coalesce((select cursor from private.read_positions where empire_id=e and channel=case when c is null then 'forum:public' else 'forum:'||c::text end),0)) unread from private.forum_threads ft join private.forum_posts p on p.thread_id=ft.id where ft.season_id=s and ft.clan_id is not distinct from c group by ft.id having p_thread_id is not null or p_before is null or max(p.id)<p_before order by max(p.id) desc limit 50)x),'[]'),
 'conversation',case when v.id is not null then jsonb_build_object('id',v.id,'subject',v.subject,'peer',case when v.sender_id=e and v.planet_label is not null then v.planet_label else (private.social_author(case when v.sender_id=e then v.recipient_id else v.sender_id end)->>'username') end) end,'messages',coalesce(msgs,'[]'),
 'conversations',coalesce((select jsonb_agg(to_jsonb(x) order by x.latest::bigint desc) from(select cv.id,cv.subject,case when cv.sender_id=e and cv.planet_label is not null then cv.planet_label else (private.social_author(case when cv.sender_id=e then cv.recipient_id else cv.sender_id end)->>'username') end peer,count(m.id) count,max(m.id)::text latest,max(m.created_at) updated_at,
 coalesce(bool_or(m.author_id<>e and m.id>coalesce((select cursor from private.read_positions where empire_id=e and channel='conversation:'||cv.id),0)),false) unread
 from private.conversations cv join private.messages m on m.conversation_id=cv.id where cv.season_id=s and (cv.sender_id=e or cv.recipient_id=e) group by cv.id having p_conversation_id is not null or p_before is null or max(m.id)<p_before order by max(m.id) desc limit 50)x),'[]')) into r;
 return r;end $$;

create function private.social_targets(p_kind text,p_query text) returns jsonb language plpgsql security definer set search_path='' as $$
declare e uuid;s uuid;begin e:=private.active_player_id();select season_id into s from public.empires where id=e;
 if char_length(btrim(p_query))<2 then return '[]';end if;
 if p_kind='player' then return coalesce((select jsonb_agg(to_jsonb(x)) from(select p.username label,e2.id id from public.empires e2 join public.profiles p on p.id=e2.player_id where e2.season_id=s and e2.id<>e and position(lower(btrim(p_query)) in lower(p.username))>0 order by p.username limit 15)x),'[]');
 elsif p_kind='planet' then return coalesce((select jsonb_agg(to_jsonb(x)) from(select p.name label,p.id from public.planets p where p.season_id=s and p.owner_empire_id is not null and p.owner_empire_id<>e and position(lower(btrim(p_query)) in lower(p.name))>0 order by p.name limit 15)x),'[]');
 else raise exception 'Destinataire invalide.';end if;end $$;

create function private.social_command(p_action text,p_args jsonb,p_request_id uuid) returns jsonb language plpgsql security definer set search_path='' as $$
declare e uuid;s uuid;c uuid;t uuid;v private.conversations%rowtype;target uuid;pid uuid;label text;rid uuid;body text;title text;payload jsonb;prev private.social_commands%rowtype;r jsonb;begin
 -- Serialize social commands by player; clan changes use the same season lock.
 select id into s from public.seasons where status='alpha' for update;e:=private.active_player_id();
 if p_request_id is null or p_action is null or p_args is null then raise exception 'Commande invalide.';end if;
 payload:=jsonb_build_object('action',p_action,'args',p_args);select * into prev from private.social_commands where empire_id=e and request_id=p_request_id;
 if found then if prev.payload<>payload then raise exception 'Identifiant déjà utilisé.';end if;return prev.result;end if;
 if p_action='signature' then
  body:=coalesce(p_args->>'signature','');if char_length(body)>280 then raise exception 'Signature limitée à 280 caractères.';end if;
  update public.profiles set signature=body where id=auth.uid();r:=jsonb_build_object('ok',true);
 else
  body:=btrim(p_args->>'body');title:=btrim(p_args->>'title');
  if body is null or char_length(body) not between 1 and 5000 then raise exception 'Message requis, 5 000 caractères maximum.';end if;
  if (select count(*) from private.forum_posts where author_id=e and created_at>clock_timestamp()-interval '1 minute')+(select count(*) from private.messages where author_id=e and created_at>clock_timestamp()-interval '1 minute')>=20 then raise exception 'Trop de messages. Réessayez dans une minute.';end if;
  if p_action in ('thread','message') and (title is null or char_length(title) not between 3 and 120) then raise exception 'Titre requis, de 3 à 120 caractères.';end if;
  if p_action='thread' then
   if p_args->>'scope'='clan' then select clan_id into c from private.clan_memberships where empire_id=e;if c is null then raise exception 'Clan inaccessible.' using errcode='42501';end if;
   elsif p_args->>'scope' is distinct from 'public' then raise exception 'Forum invalide.';end if;
   insert into private.forum_threads(season_id,clan_id,author_id,title) values(s,c,e,title) returning id into t;
   insert into private.forum_posts(thread_id,author_id,body) values(t,e,body);r:=jsonb_build_object('thread_id',t);
  elsif p_action='reply' then
   select f.id into t from private.forum_threads f where f.id=(p_args->>'thread_id')::uuid and f.season_id=s and (f.clan_id is null or exists(select 1 from private.clan_memberships where empire_id=e and clan_id=f.clan_id));
   if t is null then raise exception 'Discussion inaccessible.' using errcode='42501';end if;
   insert into private.forum_posts(thread_id,author_id,body) values(t,e,body);r:=jsonb_build_object('thread_id',t);
  elsif p_action='message' then
   if p_args->>'kind'='planet' then
    select owner_empire_id,id,name into target,pid,label from public.planets where id=(p_args->>'target_id')::uuid and season_id=s;
   elsif p_args->>'kind'='player' then select id into target from public.empires where id=(p_args->>'target_id')::uuid and season_id=s;
   else raise exception 'Destinataire invalide.';end if;
   if target is null or target=e then raise exception 'Destinataire indisponible.';end if;
   insert into private.conversations(season_id,sender_id,recipient_id,planet_id,planet_label,subject) values(s,e,target,pid,label,title) returning id into rid;
   insert into private.messages(conversation_id,author_id,body) values(rid,e,body);r:=jsonb_build_object('conversation_id',rid);
  elsif p_action='respond' then
   select * into v from private.conversations where id=(p_args->>'conversation_id')::uuid and season_id=s and (sender_id=e or recipient_id=e);
   if not found then raise exception 'Conversation inaccessible.' using errcode='42501';end if;
   insert into private.messages(conversation_id,author_id,body) values(v.id,e,body);r:=jsonb_build_object('conversation_id',v.id);
  else raise exception 'Action inconnue.';end if;
 end if;
 insert into private.social_commands(empire_id,request_id,payload,result) values(e,p_request_id,payload,r);return r;
end $$;

-- Authenticated players can display commander portraits in the social UI.
create function private.social_avatar(p_path text) returns boolean language plpgsql security definer set search_path='' as $$
begin perform private.active_player_id();return exists(select 1 from public.profiles where avatar_path=p_path);exception when others then return false;end $$;
revoke all on function private.social_avatar(text) from public,anon,authenticated;
grant execute on function private.social_avatar(text) to authenticated;
create policy social_avatar_read on storage.objects for select to authenticated using(bucket_id='avatars' and private.social_avatar(name));

create function public.social_status() returns jsonb language sql security invoker set search_path='' as $$select private.social_status();$$;
create function public.social_feed(p_scope text default 'public',p_thread_id uuid default null,p_conversation_id uuid default null,p_before bigint default null) returns jsonb language sql security invoker set search_path='' as $$select private.social_feed(p_scope,p_thread_id,p_conversation_id,p_before);$$;
create function public.social_targets(p_kind text,p_query text) returns jsonb language sql security invoker set search_path='' as $$select private.social_targets(p_kind,p_query);$$;
create function public.social_command(p_action text,p_args jsonb,p_request_id uuid) returns jsonb language sql security invoker set search_path='' as $$select private.social_command(p_action,p_args,p_request_id);$$;
create function public.social_read(p_channel text,p_cursor bigint) returns void language sql security invoker set search_path='' as $$select private.social_read(p_channel,p_cursor);$$;
revoke all on function private.social_status(),public.social_status(),private.social_feed(text,uuid,uuid,bigint),public.social_feed(text,uuid,uuid,bigint),private.social_targets(text,text),public.social_targets(text,text),private.social_command(text,jsonb,uuid),public.social_command(text,jsonb,uuid),private.social_read(text,bigint),public.social_read(text,bigint) from public,anon,authenticated;
grant execute on function private.social_status(),public.social_status(),private.social_feed(text,uuid,uuid,bigint),public.social_feed(text,uuid,uuid,bigint),private.social_targets(text,text),public.social_targets(text,text),private.social_command(text,jsonb,uuid),public.social_command(text,jsonb,uuid),private.social_read(text,bigint),public.social_read(text,bigint) to authenticated;
