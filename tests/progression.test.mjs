import test from 'node:test';
import assert from 'node:assert/strict';
import {militaryTestDatabase} from '../scripts/test-military-sql.mjs';
import {civilizationQuote,assimilationProgress,civilizationView} from '../dist/progression.js';
test('Civilization quotes sum server prices, reject invalid quantities and clamp progress',()=>{
 const p={tail_level:1,prices:{2:80000,3:144200}};assert.deepEqual(civilizationQuote(p,2),{cost:224200,days:6,lastLevel:3});assert.equal(civilizationQuote(p,0),null);assert.equal(civilizationQuote(p,1.5),null);assert.equal(civilizationQuote({...p,tail_level:40},1),null);
 const j={started_at:'2026-11-01T00:00:00Z',finishes_at:'2026-11-04T00:00:00Z'};assert.equal(assimilationProgress(j,'2026-11-02T12:00:00Z'),50);assert.equal(assimilationProgress(j,'2026-10-31T00:00:00Z'),0);assert.equal(assimilationProgress(j,'2026-11-05T00:00:00Z'),100);
});
test('Civilization investment and rank lifecycle in isolated Postgres',async t=>{
 const db=await militaryTestDatabase();let scenarioActive=false;const query=db.query.bind(db);
 db.query=async(...args)=>{if(!scenarioActive)return query(...args);await db.exec('savepoint civ_statement');try{const r=await query(...args);await db.exec('release savepoint civ_statement');return r;}catch(error){await db.exec('rollback to savepoint civ_statement;release savepoint civ_statement');throw error;}};
 const one=async(sql,args=[])=>(await db.query(sql,args)).rows[0];
 const uid='41111111-1111-4111-8111-111111111111',other='42222222-2222-4222-8222-222222222222';await db.query('insert into auth.users(id) values($1),($2)',[uid,other]);
 const login=async id=>db.query("select set_config('request.jwt.claim.sub',$1,false)",[id]);
 await login(uid);const e=(await one("select public.start_player('QA_Civilization_UI','Nova Prime') id")).id;await login(other);const e2=(await one("select public.start_player('QA_Civ_Enemy','Other Prime') id")).id;await login(uid);
 const p=await one('select * from public.planets where owner_empire_id=$1',[e]),enemy=await one('select * from public.planets where owner_empire_id=$1',[e2]);
 await db.query('update public.empires set treasury=10000000 where id=$1',[e]);
 const dashboard=async()=>(await one('select public.progression_dashboard() data')).data;
 const invest=async(quantity=1,level=1,tail=1,request=crypto.randomUUID(),world=p.id)=>(await one('select public.invest_civilization($1,$2,$3,$4,$5) data',[world,quantity,level,tail,request])).data;
 const scenario=async(name,fn)=>t.test(name,async()=>{await db.exec('begin');scenarioActive=true;try{await fn();}finally{scenarioActive=false;await db.exec('rollback');}});
 await scenario('Civilization starts at 80k, funds a sequential queue and cannot double-charge retries',async()=>{
  const before=(await dashboard()).treasury,id=crypto.randomUUID();const r=await invest(2,1,1,id);await invest(2,1,1,id);
  const d=await dashboard(),w=d.planets[0];assert.equal(w.civilization,1);assert.equal(w.jobs.length,2);assert.equal(w.jobs[0].cost,80000);assert.equal(w.jobs[1].started_at,w.jobs[0].finishes_at);assert.equal(new Date(w.jobs[0].finishes_at)-new Date(w.jobs[0].started_at),72*3600000);assert.equal(d.treasury,before-r.cost);
  await assert.rejects(invest(1,1,1),/devis/);await assert.rejects(invest(1,1,3,id),/déjà utilisé/);
  await db.exec("select private.economy_process(now()+interval '72 hours')");let row=await one('select civilization from public.planets where id=$1',[p.id]);assert.equal(row.civilization,2);
  await db.exec("select private.economy_process(now()+interval '144 hours')");row=await one('select civilization from public.planets where id=$1',[p.id]);assert.equal(row.civilization,3);
  await db.exec("select private.economy_process(now()+interval '144 hours')");assert.equal((await one('select civilization from public.planets where id=$1',[p.id])).civilization,3);
 });
 await scenario('Separate worlds progress in parallel and two worlds plus civ2 earn the first promotion',async()=>{
  const second=(await one("insert into public.planets(season_id,owner_empire_id,name,race,resource) values($1,$2,'Second World','elys','ferros') returning id",[p.season_id,e])).id;
  await invest();await invest(1,1,1,crypto.randomUUID(),second);
  await db.exec("select private.economy_process(now()+interval '72 hours')");const d=await dashboard();assert.equal(d.rank.name,'Aspirant de Flotte');assert.equal(d.rank.civilization_points,400);assert.ok(d.planets.every(w=>w.civilization===2));
  await db.query('update public.planets set civilization=1 where id=$1',[second]);assert.equal((await dashboard()).rank.civilization_points,300);
 });
 await scenario('Capture cancels prepaid jobs without granting their levels or refunds',async()=>{
  await invest(2);const cash=(await dashboard()).treasury;await db.query('update public.planets set owner_empire_id=$1 where id=$2',[e2,p.id]);assert.equal((await one('select treasury from public.empires where id=$1',[e])).treasury,cash);await db.exec("select private.economy_process(now()+interval '8 days')");
  assert.equal((await one('select civilization from public.planets where id=$1',[p.id])).civilization,1);assert.equal((await one('select count(*) n from private.civilization_jobs where planet_id=$1 and cancelled_at is not null',[p.id])).n,2);

 });
 await scenario('Maximum, missing or stale quotes, ownership, debt and funds are checked by the server',async()=>{
  await assert.rejects(invest(1,1,1,crypto.randomUUID(),enemy.id),/inaccessible/);await assert.rejects(invest(0),/invalide/);await assert.rejects(invest(1,null,1),/devis/);
  await db.query('update public.empires set treasury=79999 where id=$1',[e]);await assert.rejects(invest(),/Trésorerie/);await db.query('update public.empires set treasury=10000000,maintenance_debt=1 where id=$1',[e]);await assert.rejects(invest(),/entretien/);await db.query('update public.empires set maintenance_debt=0 where id=$1',[e]);
  await db.query('update public.planets set civilization=39 where id=$1',[p.id]);await invest(1,39,39);await assert.rejects(invest(1,39,40),/maximal/);await db.exec("select private.economy_process(now()+interval '72 hours')");assert.equal((await dashboard()).planets[0].civilization,40);await assert.rejects(invest(1,40,40),/maximal/);
 });
 await scenario('Only completed production and actual recruitment count; transfers never add merit',async()=>{
  const initial=await dashboard();assert.equal(initial.rank.raw_production_points,0);assert.equal(initial.rank.score,100);await db.query("update public.planets set race='elys',resource='aurite' where id=$1",[p.id]);
  await one('select public.military_command($1,$2::jsonb,$3)', ['ship',JSON.stringify({planet_id:p.id,kind:'bomber',quantity:1}),crypto.randomUUID()]);
  assert.equal((await dashboard()).rank.raw_production_points,0);await db.query("update private.ship_jobs set finishes_at=now()-interval '1 second' where empire_id=$1",[e]);await db.exec('select private.economy_process()');
  const merit=await one('select * from private.player_merit where empire_id=$1',[e]);assert.equal(merit.produced_bombers,1);
  const f=(await one('select public.military_command($1,$2::jsonb,$3) data',['assemble',JSON.stringify({planet_id:p.id,name:'Transfer',scouts:0,bombers:1,fighters:0}),crypto.randomUUID()])).data.id;
  await one('select public.military_command($1,$2::jsonb,$3)',['load',JSON.stringify({fleet_id:f,soldiers:10}),crypto.randomUUID()]);await one('select public.military_command($1,$2::jsonb,$3)',['disband',JSON.stringify({fleet_id:f}),crypto.randomUUID()]);
  assert.equal((await dashboard()).rank.raw_production_points,4);await db.exec("select private.economy_process(now()+interval '24 hours')");assert.equal((await one('select produced_soldiers from private.player_merit where empire_id=$1',[e])).produced_soldiers,1);
 });
 await scenario('Battle merit is shared by contribution and excludes self and clan losses',async()=>{
  const snapshot=[{empire_id:e,side:'attack',race:'elys',scouts:0,bombers:0,fighters:1,ground:5},{empire_id:e2,side:'attack',race:'elys',scouts:0,bombers:0,fighters:1,ground:5}];
  await db.query("select private.credit_battle_losses($1::jsonb,null,'defend',32,10)",[JSON.stringify(snapshot)]);
  assert.equal(Number((await one('select destroyed_points from private.player_merit where empire_id=$1',[e])).destroyed_points),21);assert.equal(Number((await one('select destroyed_points from private.player_merit where empire_id=$1',[e2])).destroyed_points),21);
  await db.query("select private.credit_battle_losses($1::jsonb,$2,'defend',32,10)",[JSON.stringify(snapshot),e]);assert.equal(Number((await one('select destroyed_points from private.player_merit where empire_id=$1',[e])).destroyed_points),21);
  const clan=(await one("insert into public.clans(season_id,name) values($1,'QA Test Clan') returning id",[p.season_id])).id;
  await db.query("insert into private.clan_memberships(empire_id,clan_id,season_id,role) values($1,$3,$4,'founder'),($2,$3,$4,'member')",[e,e2,clan,p.season_id]);
  await db.query("select private.credit_battle_losses($1::jsonb,$2,'defend',32,10)",[JSON.stringify(snapshot),e]);assert.equal(Number((await one('select destroyed_points from private.player_merit where empire_id=$1',[e2])).destroyed_points),42);
 });
 await scenario('Grand Amiral requires three advanced worlds, combat and score; production alone is capped',async()=>{
  await db.query('update public.planets set civilization=15 where id=$1',[p.id]);await db.query("insert into public.planets(season_id,owner_empire_id,name,race,resource,civilization) values($1,$2,'Advanced Two','elys','aurite',15),($1,$2,'Advanced Three','elys','aurite',15)",[p.season_id,e]);
  await db.query('insert into private.player_merit(empire_id,produced_soldiers,destroyed_points) values($1,1000000,0)',[e]);let r=(await dashboard()).rank;assert.equal(r.production_points,1800);assert.notEqual(r.name,'Grand Amiral');
  await db.query('update private.player_merit set destroyed_points=4000 where empire_id=$1',[e]);r=(await dashboard()).rank;assert.equal(r.name,'Grand Amiral');assert.equal(r.score,10300);
  await db.query('update public.planets set civilization=14 where id=$1',[p.id]);assert.notEqual((await dashboard()).rank.name,'Grand Amiral');
 });
 await scenario('Score equals displayed components while fractional merit is retained',async()=>{
  await db.query('insert into private.player_merit(empire_id,produced_soldiers,destroyed_points) values($1,3,.6)',[e]);let r=(await dashboard()).rank;assert.equal(r.score,r.civilization_points+r.production_points+r.combat_points);assert.equal(r.score,100);
  await db.query('update private.player_merit set produced_soldiers=6,destroyed_points=1.2 where empire_id=$1',[e]);r=(await dashboard()).rank;assert.equal(r.score,102);
 });
 await scenario('New progression endpoints and private metrics enforce authentication and ownership',async()=>{
  await db.exec('set role authenticated');const d=await dashboard();assert.equal(d.planets.length,1);await assert.rejects(db.query('select * from private.player_merit'),/permission denied/);await assert.rejects(db.query('select private.player_rank($1)',[e2]),/permission denied/);await assert.rejects(db.query("update public.empires set grade='Grand Amiral'"),/permission denied/);await assert.rejects(invest(1,1,1,crypto.randomUUID(),enemy.id),/inaccessible/);await db.exec('reset role;set role anon');await assert.rejects(dashboard(),/permission denied/);await db.exec('reset role');
 });
 const sample=await dashboard();sample.planets[0].name='<img onerror=alert(1)>';const html=civilizationView(sample,null);assert.doesNotMatch(html,/<img onerror/);assert.match(html,/80 000 Þ/);
 await db.close();
});
