import test from 'node:test';
import assert from 'node:assert/strict';
import {militaryTestDatabase} from '../scripts/test-military-sql.mjs';
import {forumView,messagesView,signatureView} from '../dist/social.js';

test('Social content and signatures are escaped, unread bodies are distinct',()=>{
 const author={username:'<script>x</script>',grade:'Fleet Admiral',signature:'<img onerror=x>',avatar:null};
 const html=forumView({scope:'public',data:{thread:{id:'a',title:'<bad>'},posts:[{id:'1',body:'<svg onload=x>',created_at:new Date().toISOString(),author,unread:true}]}},null);
 assert.ok(html.includes('&lt;svg'));assert.ok(html.includes('is-unread'));assert.ok(html.includes('Fleet Admiral'));assert.ok(!html.includes('<script>'));assert.ok(signatureView('</textarea><script>').includes('&lt;/textarea&gt;'));
 assert.ok(messagesView({data:{conversations:[]}}).includes('Aucune transmission'));
});

test('Forum, private correspondence, unread cursors and political cooldown enforce real authorization',async t=>{
 const db=await militaryTestDatabase();const q=async(sql,args=[])=>(await db.query(sql,args)).rows[0];
 const ids=['61111111-1111-4111-8111-111111111111','62222222-2222-4222-8222-222222222222','63333333-3333-4333-8333-333333333333'];const empires=[],planets=[];
 const login=async i=>db.query("select set_config('request.jwt.claim.sub',$1,false)",[ids[i]]);
 for(let i=0;i<3;i++){await db.query('insert into auth.users(id) values($1)',[ids[i]]);await login(i);empires.push((await q('select public.start_player($1,$2) id',['QA_Social_'+i,'World Social '+i])).id);planets.push((await q('select id from public.planets where owner_empire_id=$1',[empires[i]])).id);}
 const command=async(action,args,id=crypto.randomUUID())=>(await q('select public.social_command($1,$2::jsonb,$3) result',[action,JSON.stringify(args),id])).result;
 const feed=async(scope='public',thread=null,conv=null,before=null)=>(await q('select public.social_feed($1,$2,$3,$4) data',[scope,thread,conv,before])).data;
 const status=async()=>(await q('select public.social_status() data')).data;
 const read=async(channel,cursor)=>q('select public.social_read($1,$2)',[channel,cursor]);
 await t.test('New accounts receive 150k; first policy change locks the planet for 72 hours',async()=>{
  await login(0);assert.equal((await q('select treasury from public.empires where id=$1',[empires[0]])).treasury,150000);
  const args=[planets[0],'tyrannie','conseil',crypto.randomUUID()];await q('select public.set_governance($1,$2,$3,$4)',args);const first=await q('select governance_changed_at from public.planets where id=$1',[planets[0]]);await q('select public.set_governance($1,$2,$3,$4)',args);assert.deepEqual(await q('select governance_changed_at from public.planets where id=$1',[planets[0]]),first);
  await assert.rejects(q('select public.set_governance($1,$2,$3,$4)',[planets[0],'conseil','tyrannie',crypto.randomUUID()]),/Changement politique disponible/);
  await db.query("update public.planets set governance_changed_at=now()-interval '72 hours' where id=$1",[planets[0]]);await q('select public.set_governance($1,$2,$3,$4)',[planets[0],'conseil','tyrannie',crypto.randomUUID()]);
 });
 let thread,clan,clanThread,conversation;
 await t.test('Public threads, signatures, replies and idempotent retries',async()=>{
  await command('signature',{signature:'Étoiles <b>libres</b>'});const request=crypto.randomUUID(),args={scope:'public',title:'Premier contact',body:'Bonjour à tous'};
  thread=(await command('thread',args,request)).thread_id;assert.equal((await command('thread',args,request)).thread_id,thread);await assert.rejects(command('thread',{...args,body:'other'},request),/déjà utilisé/);
  await login(1);let f=await feed('public',thread);assert.equal(f.posts.length,1);assert.equal(f.posts[0].author.signature,'Étoiles <b>libres</b>');assert.ok(f.posts[0].unread);
  await read('thread:'+thread,f.posts[0].id);assert.equal((await feed('public',thread)).posts[0].unread,false);
  await command('reply',{thread_id:thread,body:'Reçu'});assert.equal((await feed('public',thread)).posts.length,2);
  await assert.rejects(command('thread',{scope:'anything',title:'Test',body:'no'}),/Forum invalide/);
 });
 await t.test('Private clan threads reject outsiders and former members, including reply and read acknowledgement',async()=>{
  await login(0);clan=(await q("select public.manage_clan('create',null,'QA Social Clan') id")).id;clanThread=(await command('thread',{scope:'clan',title:'Canal stratégique',body:'Secret clan'})).thread_id;
  await login(2);await assert.rejects(feed('clan',clanThread),/Clan inaccessible/);await assert.rejects(feed('public',clanThread),/Discussion inaccessible/);await assert.rejects(command('reply',{thread_id:clanThread,body:'Intrus'}),/inaccessible/);await assert.rejects(read('thread:'+clanThread,'1'),/Lecture invalide/);
  await login(1);await q("select public.manage_clan('join',$1,null)",[clan]);const request=(await q("select public.clan_dashboard() d")).d.outgoing[0].id;await login(0);await q("select public.review_clan_request($1,true)",[request]);await login(1);assert.equal((await feed('clan',clanThread)).posts[0].body,'Secret clan');await q("select public.manage_clan('leave',$1,null)",[clan]);await assert.rejects(feed('clan',clanThread),/Clan inaccessible/);
 });
 await t.test('Planet mail hides owner identity, binds the original recipient and rejects outsiders',async()=>{
  await login(0);const targets=(await q("select public.social_targets('planet','World Social 1') data")).data;assert.equal(targets[0].id,planets[1]);assert.deepEqual(Object.keys(targets[0]).sort(),['id','label']);
  conversation=(await command('message',{kind:'planet',target_id:planets[1],title:'Canal diplomatique',body:'Paix ?'})).conversation_id;
  let f=await feed('public',null,conversation);assert.equal(f.conversation.peer,'World Social 1');assert.ok(!JSON.stringify(f).includes('QA_Social_1'));
  await login(1);assert.equal((await status()).messages.unread,true);let inbox=await feed('public',null,conversation);await read('conversation:'+conversation,inbox.messages.at(-1).id);assert.equal((await status()).messages.unread,false);
  await command('respond',{conversation_id:conversation,body:'Oui'});await login(0);f=await feed('public',null,conversation);assert.equal(f.messages.at(-1).author.username,'World Social 1');assert.ok(!JSON.stringify(f).includes('QA_Social_1'));
  await db.query('update public.planets set owner_empire_id=$1 where id=$2',[empires[2],planets[1]]);await login(2);await assert.rejects(feed('public',null,conversation),/Conversation inaccessible/);await assert.rejects(command('respond',{conversation_id:conversation,body:'Intrus'}),/Conversation inaccessible/);await assert.rejects(read('conversation:'+conversation,'1'),/Lecture invalide/);
 });
 await t.test('Read snapshots cannot acknowledge future items or erase concurrently arriving replies',async()=>{
  await login(2);const snapshot=(await status())['forum:public'].latest;await login(1);await command('reply',{thread_id:thread,body:'Nouveau signal'});await login(2);await read('forum:public',snapshot);assert.equal((await status())['forum:public'].unread,true);await assert.rejects(read('forum:public','99999999'),/Lecture invalide/);
  await login(0);await db.query("insert into private.battle_reports(empire_id,planet_id,occurred_at,event,details) values($1,$2,now(),'arrival','{}')",[empires[0],planets[0]]);let st=await status();assert.equal(st.alerts.unread,true);assert.equal(st.alert_ids.length,1);await read('alerts',st.alerts.latest);assert.equal((await status()).alerts.unread,false);
 });
 await t.test('Authenticated clients cannot read raw social tables, anonymous clients cannot invoke RPCs',async()=>{
  await db.exec('set role authenticated');await assert.rejects(q('select * from private.messages'),/permission denied/);await assert.rejects(q('select * from private.forum_posts'),/permission denied/);assert.ok((await feed()).threads.length);
  await db.exec('reset role;set role anon');await assert.rejects(status(),/permission denied/);await assert.rejects(feed(),/permission denied/);await db.exec('reset role');
 });
 await db.close();
});
