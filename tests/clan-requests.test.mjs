import test from 'node:test';
import assert from 'node:assert/strict';
import {militaryTestDatabase} from '../scripts/test-military-sql.mjs';
import {clanPanel,clanMembersView} from '../dist/clans.js';
import {forumView} from '../dist/social.js';
import {galaxyView} from '../dist/galaxy.js';
import {planetManagementSections} from '../dist/planets.js';
import {helpTip,fortificationHelp,paranoiaHelp} from '../dist/help-tips.js';

test('Political cooldown warning precedes choices; map zoom-out adds a dead margin without moving worlds',()=>{
 const p={id:'p',governance:'conseil',civilization:1,trade_capacity:0,energy:0,energy_max:10};
 const html=planetManagementSections(p,null,null);assert.ok(html.indexOf('pendant 3 jours')<html.indexOf('class="governance-choices"'));
 const map=galaxyView([{id:'edge',designation:'Edge',x:1000,y:1000,civilization:1}],null,.5);assert.match(map,/viewBox="-1180 -1180 4360 4360"/);assert.match(map,/translate\(2000,2000\)/);assert.match(map,/data-zoom="-1" disabled/);assert.doesNotMatch(galaxyView([],null,1),/data-zoom="-1" disabled/);
 assert.match(helpTip('tip','Aide',fortificationHelp),/role="tooltip"/);assert.match(paranoiaHelp,/arrivée/);assert.match(helpTip('tip','Aide','<img>'),/&lt;img&gt;/);
});

test('Clan roster renders public tags, untagged worlds and founder decisions without leaking into the public forum',()=>{
 const d={clan:{id:'c',name:'Astre',role:'founder',member_count:1},members:[{username:'<img>',grade:'Cadet',role:'founder',planets:[{name:'Aube',tagged:true,appearance:'elys_aurite'},{name:'Nuit',tagged:false,appearance:'vael_ferros'}]}],incoming:[{id:'r',username:'Candidat',grade:'Cadet'}],outgoing:[]};
 assert.match(clanMembersView(d),/Aube.*\[Astre\]/);assert.match(clanMembersView(d),/Non taguée/);assert.doesNotMatch(clanMembersView(d),/<img>/);assert.match(clanPanel(d.clan,[],d),/data-clan-action="review"/);
 assert.doesNotMatch(forumView({scope:'public',data:null},d.clan,d),/clan-roster/);assert.match(forumView({scope:'clan',data:null},d.clan,d),/clan-roster/);
 const pending=clanPanel(null,[],{outgoing:[{id:'r',clan_name:'Astre'}]});assert.match(pending,/Annuler ma candidature/);assert.doesNotMatch(pending,/data-clan-action="join"/);
});

test('Clan applications require the current chief and expose the private roster only after approval',async t=>{
 const db=await militaryTestDatabase();let scenarioActive=false;const raw=db.query.bind(db);
 db.query=async(...args)=>{if(!scenarioActive)return raw(...args);await db.exec('savepoint stmt');try{const r=await raw(...args);await db.exec('release savepoint stmt');return r;}catch(e){await db.exec('rollback to savepoint stmt;release savepoint stmt');throw e;}};
 const q=async(s,a=[])=>(await db.query(s,a)).rows[0],users=['11111111-1111-4111-8111-111111111111','22222222-2222-4222-8222-222222222222','33333333-3333-4333-8333-333333333333'],es=[],ps=[];
 const login=i=>q("select set_config('request.jwt.claim.sub',$1,false)",[users[i]]),dashboard=async()=>(await q('select public.clan_dashboard() d')).d;
 for(let i=0;i<3;i++){await q('insert into auth.users(id) values($1)',[users[i]]);await login(i);es.push((await q('select public.start_player($1,$2) id',['QA_Clan_'+i,'Monde '+i])).id);ps.push((await q('select id from public.planets where owner_empire_id=$1',[es[i]])).id);}
 await login(0);const clan=(await q("select public.manage_clan('create',null,'Les Veilleurs') id")).id;await login(2);const other=(await q("select public.manage_clan('create',null,'Les Autres') id")).id;
 const join=()=>q("select public.manage_clan('join',$1,null)",[clan]),review=(id,accept)=>q('select public.review_clan_request($1,$2)',[id,accept]);
 const scenario=(name,run)=>t.test(name,async()=>{await db.exec('begin');scenarioActive=true;try{await run();}finally{scenarioActive=false;await db.exec('rollback');}});
 await scenario('Join retries stay pending; applicants and unrelated chiefs cannot approve; approval is replay-safe',async()=>{
  await login(1);await join();await join();let d=await dashboard();assert.equal(d.clan,null);assert.equal(d.members.length,0);assert.equal(d.outgoing.length,1);const id=d.outgoing[0].id;
  await assert.rejects(q("select public.social_feed('clan')"),/Clan inaccessible/);await assert.rejects(review(id,true),/seul le chef/);
  await login(2);await assert.rejects(review(id,true),/seul le chef/);assert.equal((await dashboard()).incoming.length,0);
  await login(0);d=await dashboard();assert.equal(d.incoming[0].username,'QA_Clan_1');assert.equal('planets' in d.incoming[0],false);await review(id,true);await review(id,true);await assert.rejects(review(id,false),/déjà été traitée/);
  await login(1);d=await dashboard();assert.equal(d.clan.role,'member');assert.equal(d.clan.member_count,2);assert.equal(d.outgoing.length,0);assert.equal(d.members.length,2);await assert.rejects(review(id,true),/seul le chef/);
  assert.equal((await q('select clan_tag_visible from public.planets where id=$1',[ps[1]])).clan_tag_visible,false);
 });
 await scenario('Cancellation, refusal and new requests cannot resurrect a stale application',async()=>{
  await login(1);await join();const first=(await dashboard()).outgoing[0].id;await assert.rejects(q("select public.manage_clan('join',$1,null)",[other]),/Annulez/);
  await login(0);await assert.rejects(q('select public.cancel_clan_request($1)',[first]),/inaccessible/);await review(first,false);
  await login(1);await join();const second=(await dashboard()).outgoing[0].id;assert.notEqual(first,second);await q('select public.cancel_clan_request($1)',[second]);await q('select public.cancel_clan_request($1)',[second]);assert.equal((await dashboard()).outgoing.length,0);
  await login(0);await assert.rejects(review(first,true),/déjà été traitée/);await assert.rejects(review(second,true),/déjà été traitée/);assert.equal((await dashboard()).clan.member_count,1);
 });
 await scenario('Members see names, worlds and public tag status; outsiders and former members cannot query that roster',async()=>{
  await login(1);await join();const id=(await dashboard()).outgoing[0].id;await login(0);await review(id,true);await q('select public.set_planet_options($1,true,true)',[ps[0]]);
  let d=await dashboard();const a=d.members.find(x=>x.username==='QA_Clan_0'),b=d.members.find(x=>x.username==='QA_Clan_1');assert.equal(a.planets[0].tagged,true);assert.equal(b.planets[0].name,'Monde 1');assert.equal(b.planets[0].tagged,false);
  await login(2);d=await dashboard();assert.equal(d.members.some(x=>x.username==='QA_Clan_1'),false);
  await login(1);await q("select public.manage_clan('leave',$1,null)",[clan]);d=await dashboard();assert.equal(d.clan,null);assert.deepEqual(d.members,[]);
 });
 await scenario('Leadership transfer grants request review to the new chief and removes it from the former chief',async()=>{
  await login(1);await join();let id=(await dashboard()).outgoing[0].id;await login(0);await review(id,true);await q("select public.manage_clan('leave',$1,null)",[clan]);await join();id=(await dashboard()).outgoing[0].id;await assert.rejects(review(id,true),/seul le chef/);
  await login(1);assert.equal((await dashboard()).clan.role,'founder');await review(id,true);assert.equal((await dashboard()).clan.member_count,2);
 });
 await scenario('Requests and privileged endpoints stay inaccessible to direct or anonymous clients',async()=>{
  assert.equal((await q("select has_table_privilege('authenticated','private.clan_requests','select') allowed")).allowed,false);
  await db.exec('set local role anon');await assert.rejects(dashboard(),/permission denied/);await assert.rejects(review('00000000-0000-4000-8000-000000000001',true),/permission denied/);await db.exec('reset role');
 });
 await db.close();
});
