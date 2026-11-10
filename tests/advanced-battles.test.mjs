import {researchFixture} from './research-fixtures.mjs';
import test from 'node:test';
import assert from 'node:assert/strict';
import {militaryTestDatabase} from '../scripts/test-military-sql.mjs';
import {travelSeconds,transitView,missionView} from '../dist/military.js';

test('Transit presentation exposes redirect orders and three-and-a-half-day diagonal travel',()=>{
 assert.equal(travelSeconds(0),1800);assert.equal(travelSeconds(Math.sqrt(2000000)),302400);
 const f={id:'f',name:'<script>',status:'transit',mission:'attack',origin:'A',destination:'B',departed_at:new Date(Date.now()-3600000),arrives_at:new Date(Date.now()+3600000),scouts:1,bombers:0,fighters:0,soldiers:0,ground_soldiers:0};
 assert.match(transitView({fleets:[f]}),/Changer de destination/);assert.doesNotMatch(transitView({fleets:[f]}),/<script>/);assert.match(missionView(f,[]),/data-military="redirect"/);
});

test('Advanced warfare rules are authoritative and conserve units in isolated Postgres',async t=>{
 const db=await militaryTestDatabase();const q=async(s,a=[])=>(await db.query(s,a)).rows[0];
 const users=['11111111-1111-4111-8111-111111111111','22222222-2222-4222-8222-222222222222'];
 const login=i=>q("select set_config('request.jwt.claim.sub',$1,false)",[users[i]]);const es=[],ps=[];
 for(let i=0;i<2;i++){await q('insert into auth.users(id) values($1)',[users[i]]);await login(i);es.push((await q('select public.start_player($1,$2) id',['QA_Battle_'+i,'Prime '+i])).id);ps.push(await q('select * from public.planets where owner_empire_id=$1',[es[i]]));}
 await login(0);
 const cmd=async(action,args,id=crypto.randomUUID())=>(await q('select public.military_command($1,$2,$3) r',[action,args,id])).r;
 const fleet=async({owner=0,mission='attack',ships=0,ground=0,cargo=0,ready='-infinity',location=ps[1].id}={})=>(await q("insert into private.fleets(empire_id,season_id,name,race,supply_planet,planet_id,origin_id,mission,fighters,ground_soldiers,soldiers,ground_ready_at) values($1,$2,'QA Battle','elys',$3,$4,$3,$5,$6,$7,$8,$9) returning id",[es[owner],ps[0].season_id,ps[owner].id,location,mission,ships,ground,cargo,ready])).id;
 const scenario=async(name,run)=>t.test(name,async()=>{await db.exec('begin');try{await run();}finally{await db.exec('rollback');}});
 await scenario('Redirect interpolates from current position, preserves mission, and replays exactly once',async()=>{
  const id=await fleet({ships:1,location:ps[0].id,mission:'defend'});await cmd('dispatch',{fleet_id:id,target_id:ps[1].id,mission:'attack'});
  await q("update private.fleets set departed_at=now()-interval '1 hour',arrives_at=now()+interval '1 hour' where id=$1",[id]);
  const before=await q('select * from private.fleet_position((select f from private.fleets f where id=$1),now())',[id]);
  const target=await q('select id from public.planets where owner_empire_id is null limit 1'),rid=crypto.randomUUID();await cmd('redirect',{fleet_id:id,target_id:target.id},rid);
  let f=await q('select * from private.fleets where id=$1',[id]);assert.equal(f.route_x,before.x);assert.equal(f.route_y,before.y);assert.equal(f.mission,'attack');assert.equal(f.fighters,1);const at=f.arrives_at;
  await cmd('redirect',{fleet_id:id,target_id:target.id},rid);assert.equal((await q('select arrives_at from private.fleets where id=$1',[id])).arrives_at.getTime(),at.getTime());
  await login(1);await db.exec('savepoint foreign_refusal');await assert.rejects(cmd('redirect',{fleet_id:id,target_id:ps[0].id}),/indisponible/);await db.exec('rollback to savepoint foreign_refusal');await login(0);
 });
 await scenario('Arrival blocks dispatch, loading and disband; mode changes impose N/A and stack defense delay',async()=>{
  const id=await fleet({ships:1,location:ps[0].id,mission:'defend'});await cmd('dispatch',{fleet_id:id,target_id:ps[1].id,mission:'defend'});await q("update private.fleets set arrives_at=now()-interval '1 minute' where id=$1",[id]);await q('select private.economy_process()');
  for(const [a,args] of [['dispatch',{target_id:ps[0].id,mission:'defend'}],['load',{soldiers:0}],['disband',{}]]){await db.exec('savepoint refusal');await assert.rejects(cmd(a,{fleet_id:id,...args}),/N\/A/);await db.exec('rollback to savepoint refusal');}
  await cmd('mission',{fleet_id:id,mission:'attack'});let f=await q('select * from private.fleets where id=$1',[id]);assert.ok(f.ground_ready_at>new Date());const old=f.unavailable_until;
  await cmd('mission',{fleet_id:id,mission:'defend'});f=await q('select * from private.fleets where id=$1',[id]);assert.equal(f.unavailable_until-old,3600000);
 });
 await scenario('Paranoia forces non-clan defensive arrivals into attack; capture inverts incoming missions',async()=>{
  await q('update public.planets set paranoid=true where id=$1',[ps[1].id]);const id=await fleet({ships:1,location:ps[0].id,mission:'defend'});await cmd('dispatch',{fleet_id:id,target_id:ps[1].id,mission:'defend'});await q("update private.fleets set arrives_at=now()-interval '1 second' where id=$1",[id]);await q('select private.economy_process()');assert.equal((await q('select mission from private.fleets where id=$1',[id])).mission,'attack');
  const incoming=await fleet({ships:1,location:ps[0].id,mission:'defend'});await cmd('dispatch',{fleet_id:incoming,target_id:ps[1].id,mission:'defend'});await q('update public.planets set owner_empire_id=$1 where id=$2',[es[0],ps[1].id]);assert.equal((await q('select mission from private.fleets where id=$1',[incoming])).mission,'attack');
 });
 await scenario('Unavailable armies take damage but cannot fire, prevent capture or be teleported',async()=>{
  await q("update public.planets set scouts=0,fighters=0,bombers=0,soldiers=100,garrison_ready_at=now()+interval '1 hour' where id=$1",[ps[1].id]);const id=await fleet({ground:10,ships:1});await q('select private.resolve_battle($1,now())',[ps[1].id]);assert.equal((await q('select ground_soldiers from private.fleets where id=$1',[id])).ground_soldiers,10);assert.equal((await q('select owner_empire_id from public.planets where id=$1',[ps[1].id])).owner_empire_id,es[0]);
  assert.equal(Number((await q('select sum(ground_soldiers) n from private.fleets where empire_id=$1 and planet_id=$2',[es[1],ps[1].id])).n),100);
 });
 await scenario('A purely unavailable attacking army still suffers defending ground fire',async()=>{
  await q("update public.planets set race='elys',scouts=0,bombers=0,fighters=0,soldiers=100 where id=$1",[ps[1].id]);const id=await fleet({ground:200,ready:new Date(Date.now()+3600000).toISOString()});await q('select private.resolve_battle($1,now())',[ps[1].id]);assert.equal((await q('select ground_soldiers from private.fleets where id=$1',[id])).ground_soldiers,196);assert.equal((await q('select soldiers from public.planets where id=$1',[ps[1].id])).soldiers,100);
 });
 await scenario('Space control gates bombing and 100 ships blockade both endpoints until two hours after release',async()=>{
  await q("update public.planets set race='elys',scouts=0,bombers=0,fighters=10,soldiers=100,trade_capacity=5,resource='aurite' where id=$1",[ps[1].id]);await q("update public.planets set trade_capacity=5,resource='biomasse' where id=$1",[ps[0].id]);
  await q("select public.trade_command('propose',$1,$2,5,null,$3)",[ps[0].id,ps[1].id,crypto.randomUUID()]);const id=await fleet({ships:10});await q('update private.fleets set bombers=100 where id=$1',[id]);await q('select private.resolve_battle($1,now())',[ps[1].id]);assert.equal((await q('select soldiers from public.planets where id=$1',[ps[1].id])).soldiers,100);
  await q('update private.fleets set fighters=100 where id=$1',[id]);await q('select private.sync_planet_war($1,now())',[ps[1].id]);assert.equal((await q('select blockaded from public.planets where id=$1',[ps[1].id])).blockaded,true);
  assert.equal(Number((await q('select trade from private.planet_daily_rates($1)',[ps[0].id])).trade),0);
  await q("update private.fleets set status='disbanded' where id=$1",[id]);await q('select private.sync_planet_war($1,now())',[ps[1].id]);assert.equal(Number((await q('select trade from private.planet_daily_rates($1)',[ps[0].id])).trade),0);
  await q("select set_config('lw.rate_at',(now()+interval '2 hours')::text,true)");assert.ok(Number((await q('select trade from private.planet_daily_rates($1)',[ps[0].id])).trade)>0);
 });
 await scenario('Ground superiority pauses recruitment and queues, and locks trade; capture refunds industry and loses assimilation',async()=>{
  await q('update public.empires set treasury=1000000 where id=$1',[es[1]]);await login(1);await cmd('ship',{planet_id:ps[1].id,kind:'fighter',quantity:1});await q('select public.invest_civilization($1,1,1,1,$2)',[ps[1].id,crypto.randomUUID()]);await login(0);
  await q('update public.planets set soldiers=1 where id=$1',[ps[1].id]);await fleet({ground:10});await q('select private.sync_planet_war($1,now())',[ps[1].id]);assert.ok((await q('select paused_at from private.ship_jobs where planet_id=$1',[ps[1].id])).paused_at);
  await login(1);await db.exec('savepoint blocked');await assert.rejects(cmd('ship',{planet_id:ps[1].id,kind:'scout',quantity:1}),/suspendue/);await db.exec('rollback to savepoint blocked');await login(0);
  const cash=(await q('select treasury from public.empires where id=$1',[es[1]])).treasury;await q('update public.planets set soldiers=0 where id=$1',[ps[1].id]);await q('select private.resolve_battle($1,now())',[ps[1].id]);assert.equal((await q('select treasury from public.empires where id=$1',[es[1]])).treasury,cash+16000);assert.ok((await q('select cancelled_at from private.civilization_jobs where planet_id=$1',[ps[1].id])).cancelled_at);
 });
 await scenario('Fortifications hit 0, 60 and 95 percent, and renamed untagged worlds have public names',async()=>{
  for(const [days,bonus] of [[7,0],[60,.6],[150,.95]])assert.ok(Math.abs(Number((await q("select private.fortification(p,p.captured_at+make_interval(days=>$2)) n from public.planets p where id=$1",[ps[1].id,days])).n)-bonus)<.000001);
  await q("update public.planets set name='Aube libre',clan_tag_visible=false where id=$1",[ps[1].id]);assert.equal((await q('select designation from private.galaxy_signals() where id=$1',[ps[1].id])).designation,'Aube libre');
 });
 await scenario('Teleported troops remain damageable but cannot load, teleport or act for one hour; energy gains one per hour',async()=>{
  await q('update public.empires set treasury=1000000 where id=$1',[es[0]]);
  const tech=async(action,args)=>action==='research'?researchFixture(db,q,args):(await q('select public.technology_command($1,$2,$3) r',[action,args,crypto.randomUUID()])).r;
  await tech('research',{technology:'energy'});await tech('research',{technology:'teleport'});
  const target=await q('select id from public.planets where owner_empire_id is null limit 1');await q('update public.planets set owner_empire_id=$1 where id=$2',[es[0],target.id]);await q("update public.planets set teleport_ready_at=now(),garrison_ready_at=now() where id=$1",[target.id]);
  await tech('teleport',{origin_id:ps[0].id,target_id:target.id,quantity:10});let f=await q('select * from private.fleets where planet_id=$1 and empire_id=$2',[target.id,es[0]]);assert.ok(f.ground_ready_at>new Date());
  await db.exec('savepoint not_ready');await assert.rejects(tech('teleport',{origin_id:target.id,target_id:ps[0].id,quantity:1}),/Soldats.*disponibles/);await db.exec('rollback to savepoint not_ready');
  const carrier=await fleet({ships:1,mission:'defend',location:target.id});await db.exec('savepoint load_not_ready');await assert.rejects(cmd('load',{fleet_id:carrier,soldiers:1}),/Soldats.*disponibles/);await db.exec('rollback to savepoint load_not_ready');
  await q("select private.advance_planet_development($1,now()+interval '1 hour')",[ps[0].season_id]);assert.equal((await q('select energy from public.planets where id=$1',[ps[0].id])).energy,10);
 });
 await scenario('Readiness events suspend jobs at the exact hour and resume preserves remaining build time',async()=>{
  await q('update public.empires set treasury=1000000 where id=$1',[es[1]]);await login(1);await cmd('ship',{planet_id:ps[1].id,kind:'scout',quantity:1});await login(0);
  await q('update public.planets set soldiers=1 where id=$1',[ps[1].id]);const id=await fleet({ground:10,ready:new Date(Date.now()+1800000).toISOString()});
  await q("select private.economy_process(now()+interval '45 minutes')");let job=await q('select * from private.ship_jobs where planet_id=$1',[ps[1].id]);assert.ok(job.paused_at);assert.equal(job.completed_at,null);
  await q("update private.fleets set mission='defend' where id=$1",[id]);await q("select private.sync_planet_war($1,now()+interval '90 minutes')",[ps[1].id]);const resumed=await q('select * from private.ship_jobs where planet_id=$1',[ps[1].id]);assert.equal(resumed.paused_at,null);assert.ok(Math.abs(resumed.finishes_at-job.finishes_at-3600000)<1000);
 });
 await scenario('Conquest resets fortification and Tyranny, opens rename, and applies the network delay to previously owned worlds only',async()=>{
  await q("update public.planets set governance='tyrannie',captured_at=now()-interval '150 days',governance_changed_at=now(),scouts=0,bombers=0,fighters=0,soldiers=0 where id=$1",[ps[1].id]);await fleet({ground:10});await q('select private.resolve_battle($1,now())',[ps[1].id]);const p=await q('select *,private.fortification(p,now()) fort from public.planets p where id=$1',[ps[1].id]);
  assert.equal(p.governance,'conseil');assert.equal(Number(p.fort),0);assert.equal(p.name,'Signal '+p.serial);assert.equal(p.rename_available,true);assert.equal(Math.round((p.teleport_ready_at-new Date())/3600000),2);
  assert.ok((await q('select ground_ready_at from private.fleets where empire_id=$1 and planet_id=$2',[es[0],ps[1].id])).ground_ready_at>new Date());
 });
 await db.close();
});
