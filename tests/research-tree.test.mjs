import test from 'node:test';
import assert from 'node:assert/strict';
import {militaryTestDatabase} from '../scripts/test-military-sql.mjs';
import {researchTreeView} from '../dist/research-tree.js';
import {planetTechnologyModules} from '../dist/technology-actions.js';

test('Research and special projects enforce ownership, timing, costs and conserved transfers',async t=>{
 const db=await militaryTestDatabase();let scenarioActive=false;const raw=db.query.bind(db);
 db.query=async(...args)=>{if(!scenarioActive)return raw(...args);await db.exec('savepoint statement');try{const r=await raw(...args);await db.exec('release savepoint statement');return r;}catch(e){await db.exec('rollback to savepoint statement;release savepoint statement');throw e;}};
 const q=async(sql,args=[])=>(await db.query(sql,args)).rows[0],uids=[crypto.randomUUID(),crypto.randomUUID(),crypto.randomUUID()],es=[],ps=[];
 const login=i=>q("select set_config('request.jwt.claim.sub',$1,false)",[uids[i]]);
 for(let i=0;i<3;i++){await q('insert into auth.users(id) values($1)',[uids[i]]);await login(i);es.push((await q('select public.start_player($1,$2) e',['QA_Research_'+i,'Research '+i])).e);ps.push(await q('select * from public.planets where owner_empire_id=$1',[es[i]]));await q('update public.empires set treasury=100000000 where id=$1',[es[i]]);}
 await login(0);const s=ps[0].season_id;
 const grant=async(key,n=1,i=0)=>{await q('insert into private.research_levels values($1,$2,$3,now()) on conflict(empire_id,key) do update set level=excluded.level',[es[i],key,n]);if(key==='energy'||key==='teleport'){await q('insert into private.player_technologies(empire_id) values($1) on conflict do nothing',[es[i]]);await q(`update private.player_technologies set ${key==='energy'?'energy':'teleport'}_unlocked_at=now() where empire_id=$1`,[es[i]]);}};
 const tech=(action,args,id=crypto.randomUUID())=>q('select public.technology_command($1,$2,$3) r',[action,args,id]).then(x=>x.r);
 const intel=(action,args,id=crypto.randomUUID())=>q('select public.intelligence_command($1,$2,$3) r',[action,args,id]).then(x=>x.r);
 const special=(action,args,id=crypto.randomUUID())=>q('select public.special_command($1,$2,$3) r',[action,args,id]).then(x=>x.r);
 const fleet=async({i=0,location=ps[1].id,mission='attack',scouts=10,ground=0,shipsLevel=0,camo=false}={})=>{const f=await q("insert into private.fleets(empire_id,season_id,name,race,supply_planet,planet_id,origin_id,mission,scouts,ground_soldiers,ground_ready_at,camouflaged) values($1,$2,'Research fleet','elys',$3,$4,$3,$5,$6,$7,'-infinity',$8) returning id",[es[i],s,ps[i].id,location,mission,scouts,ground,camo]);await q('update private.fleets set ship_tech=$1 where id=$2',[shipsLevel,f.id]);return f.id;};
 const scenario=(name,fn)=>t.test(name,async()=>{await db.exec('begin');scenarioActive=true;try{await login(0);await fn();}finally{scenarioActive=false;await db.exec('rollback');}});
 try{
 await scenario('Catalog costs, prerequisites, one project per planet and concurrent laboratories are authoritative',async()=>{
  assert.equal(Number((await q("select sum(private.tech_price(key,1)) n from private.technology_catalog where key in('black_hole_1','black_hole_2','black_hole_3','black_hole_4')")).n),20000000);
  await assert.rejects(tech('research',{planet_id:ps[0].id,technology:'teleport'}),/Prérequis/);
  const request=crypto.randomUUID(),args={planet_id:ps[0].id,technology:'energy'};const before=(await q('select treasury from public.empires where id=$1',[es[0]])).treasury;
  const job=await tech('research',args,request);await tech('research',args,request);assert.equal((await q('select treasury from public.empires where id=$1',[es[0]])).treasury,before-150000);
  assert.equal((await q("select private.tech_level($1,'energy') n",[es[0]])).n,0);
  await assert.rejects(tech('research',{planet_id:ps[0].id,technology:'travel'}),/déjà en cours/);
  const other=await q('select id from public.planets where owner_empire_id is null limit 1');await q('update public.planets set owner_empire_id=$1 where id=$2',[es[0],other.id]);
  await assert.rejects(tech('research',{planet_id:other.id,technology:'energy'}),/déjà en recherche/);
  await tech('research',{planet_id:other.id,technology:'travel'});
  await q("select private.economy_process(now()+interval '12 hours')");assert.equal((await q("select private.tech_level($1,'energy') n",[es[0]])).n,1);assert.equal((await q("select private.tech_level($1,'travel') n",[es[0]])).n,0);
  assert.ok((await q('select completed_at from private.research_jobs where id=$1',[job.id])).completed_at);
 });
 await scenario('Capture refunds unfinished research, acquired knowledge survives and incompatible labs cannot research',async()=>{
  await q("update public.planets set race='vael' where id=$1",[ps[0].id]);await grant('infiltration');await grant('genetics_1');
  await assert.rejects(tech('research',{planet_id:ps[0].id,technology:'genetics_2'}),/incompatible/);
  const a=await tech('research',{planet_id:ps[0].id,technology:'travel'}),paid=(await q('select treasury from public.empires where id=$1',[es[0]])).treasury;
  await q('update public.planets set owner_empire_id=$1 where id=$2',[es[1],ps[0].id]);assert.equal((await q('select treasury from public.empires where id=$1',[es[0]])).treasury,paid+500000);
  assert.ok((await q('select cancelled_at from private.research_jobs where id=$1',[a.id])).cancelled_at);assert.equal((await q("select private.tech_level($1,'infiltration') n",[es[0]])).n,1);
 });
 await scenario('Travel, exploitation, TP and storage levels apply only their researched effects',async()=>{
  assert.equal((await q('select private.player_travel_seconds($1,0) n',[es[0]])).n,3600);await grant('travel',3);assert.equal((await q('select private.player_travel_seconds($1,0) n',[es[0]])).n,2211);
  const base=(await q('select private.capacity_price_for($1,30) n',[ps[0].id])).n;await grant('workers_1');assert.equal((await q('select private.capacity_price_for($1,30) n',[ps[0].id])).n,Math.ceil(base*.7));
  await q('update public.planets set civilization=5 where id=$1',[ps[0].id]);assert.equal((await q('select private.capacity_price_for($1,30) n',[ps[0].id])).n,base);
  await grant('energy');await q('update public.planets set energy=10 where id=$1',[ps[0].id]);await assert.rejects(tech('energy_capacity',{planet_id:ps[0].id,quantity:1,expected_capacity:10}),/invalide/);
  await grant('energy_magma',1);await tech('energy_capacity',{planet_id:ps[0].id,quantity:15,expected_capacity:10});assert.equal((await q('select energy_max from public.planets where id=$1',[ps[0].id])).energy_max,25);
  assert.equal((await q('select private.teleport_capacity($1) n',[es[0]])).n,1);await grant('teleport_improved',3);assert.equal((await q('select private.teleport_capacity($1) n',[es[0]])).n,5);
 });
 await scenario('Infiltration thresholds hide information, stop at target and lose a trade dependency below thirty',async()=>{
  await grant('infiltration');await q("update public.planets set resource='aurite',trade_capacity=10 where id=$1",[ps[0].id]);await q("update public.planets set resource='biomasse',trade_capacity=10 where id=$1",[ps[1].id]);
  const link=(await q("select public.trade_command('propose',$1,$2,5,null,$3) r",[ps[0].id,ps[1].id,crypto.randomUUID()])).r;
  const created=await intel('infiltrate',{planet_id:ps[0].id,target_id:ps[1].id,target_level:20});let i=await q('select * from private.infiltrations where id=$1',[created.id]);assert.deepEqual((await q('select private.infiltration_intel(i) r from private.infiltrations i where id=$1',[i.id])).r,{});
  await q("select private.advance_infiltrations($1,now()+interval '2 days')",[s]);const info=(await q('select private.infiltration_intel(i) r from private.infiltrations i where id=$1',[i.id])).r;assert.equal(info.population,ps[1].population);assert.equal('owner'in info,false);
  await q("select private.advance_infiltrations($1,now()+interval '20 days')",[s]);i=await q('select * from private.infiltrations where id=$1',[i.id]);assert.equal(Number(i.level),20);assert.equal(Number((await q('select private.infiltration_upkeep(i) n from private.infiltrations i where id=$1',[i.id])).n),100);
  await q("update private.trade_links set status='cancelled' where source_planet=$1",[ps[0].id]);await q("select private.advance_infiltrations($1,now()+interval '21 days')",[s]);assert.equal((await q('select count(*) n from private.infiltrations where id=$1',[i.id])).n,0);
 });
 await scenario('Captivity shares the cap, conserves income, freezes under security and purifies after seven days',async()=>{
  await grant('infiltration');await grant('infiltration',1,1);const target=ps[2];
  for(let i=0;i<2;i++)await q('insert into private.infiltrations(empire_id,origin_id,target_id,level,target_level,drain) values($1,$2,$3,90,90,.35)',[es[i],ps[i].id,target.id]);
  const rows=(await db.query('select private.effective_drain(i) n from private.infiltrations i where target_id=$1',[target.id])).rows;assert.ok(rows.every(r=>Number(r.n)===.175));
  const rawRate=await q('select civil,trade,trade_cost from private.planet_daily_rates_before_infiltration($1)',[target.id]),actual=await q('select civil,trade,trade_cost from private.planet_daily_rates($1)',[target.id]);
  const income=Number((await q('select sum(private.infiltration_income(i)) n from private.infiltrations i where target_id=$1',[target.id])).n);assert.ok(Math.abs(Number(rawRate.civil)+Number(rawRate.trade)-Number(rawRate.trade_cost)-Number(actual.civil)-Number(actual.trade)+Number(actual.trade_cost)-income)<1e-6);
  await grant('infiltration',1,2);await login(2);await intel('security',{planet_id:target.id,mode:'block',accuracy:50});assert.equal(Number((await q('select sum(private.effective_drain(i)) n from private.infiltrations i where target_id=$1',[target.id])).n),0);
  await q("update public.planets set governance='tyrannie' where id=$1",[target.id]);await intel('purify',{planet_id:target.id});await q("select private.advance_infiltrations($1,now()+interval '7 days')",[s]);assert.equal((await q('select count(*) n from private.infiltrations where target_id=$1',[target.id])).n,0);
 });
 await scenario('Covert capture preserves fortifications, government and ground armies without revealing its controller',async()=>{
  await q("update public.planets set governance='tyrannie',captured_at=now()-interval '60 days',scouts=0 where id=$1",[ps[1].id]);await fleet({i:1,location:ps[1].id,mission:'defend',scouts:0,ground:10});
  await q('insert into private.infiltrations(empire_id,origin_id,target_id,level,target_level) values($1,$2,$3,99,100)',[es[0],ps[0].id,ps[1].id]);await q("select private.advance_infiltrations($1,now()+interval '5 hours')",[s]);
  const p=await q('select *,private.fortification(p,now()) fort from public.planets p where id=$1',[ps[1].id]);assert.equal(p.owner_empire_id,es[0]);assert.equal(p.governance,'tyrannie');assert.equal(p.soldiers,ps[1].soldiers);assert.ok(Number(p.fort)>.59);assert.ok(new Date(p.anonymous_until)>new Date());assert.equal((await q('select sum(ground_soldiers) n from private.fleets where planet_id=$1 and empire_id=$2',[p.id,es[0]])).n,10);
 });
 await scenario('Ninety-percent infiltration grants code-free TP while a blockade removes that access',async()=>{
  for(let i=0;i<2;i++){await grant('energy',1,i);await grant('teleport',1,i);}await q("update public.planets set energy=10,teleport_ready_at=now()-interval '1 hour',garrison_ready_at='-infinity' where id in($1,$2)",[ps[0].id,ps[1].id]);
  await q('insert into private.infiltrations(empire_id,origin_id,target_id,level,target_level) values($1,$2,$3,90,90)',[es[0],ps[0].id,ps[1].id]);
  const data=(await q('select public.technology_dashboard() d')).d;assert.equal(data.targets.find(p=>p.id===ps[1].id).access,'infiltration');
  const result=await tech('teleport',{origin_id:ps[0].id,target_id:ps[1].id,quantity:3});assert.equal(result.energy_cost,3);assert.equal((await q('select energy from public.planets where id=$1',[ps[0].id])).energy,7);
  await q("insert into private.planet_security(planet_id,mode) values($1,'block')",[ps[1].id]);assert.equal((await tech('teleport',{origin_id:ps[0].id,target_id:ps[1].id,quantity:1})).ok,false);
 });
 await scenario('A basic scan charges once, takes four hours and stores the same result in its report',async()=>{
  await grant('scan_fleets');await q('update public.planets set x=1000,y=1000 where season_id=$1',[s]);await q('update public.planets set x=0,y=0,energy=10 where id=$1',[ps[0].id]);await q('update public.planets set x=1,y=1 where id=$1',[ps[1].id]);const request=crypto.randomUUID(),args={planet_id:ps[0].id,target_id:ps[1].id,kind:'fleets',mode:'basic'},cash=(await q('select treasury from public.empires where id=$1',[es[0]])).treasury;
  const r=await special('scan',args,request);await special('scan',args,request);assert.equal((await q('select treasury from public.empires where id=$1',[es[0]])).treasury,cash-80000);assert.equal((await q('select energy from public.planets where id=$1',[ps[0].id])).energy,9);
  await q("select private.advance_special_projects($1,now()+interval '4 hours')",[s]);const scan=await q('select * from private.scan_jobs where id=$1',[r.id]),report=await q("select details from private.battle_reports where empire_id=$1 and event='scan_report'",[es[0]]);assert.ok(scan.completed_at);assert.deepEqual(report.details.result,scan.result);
 });
 await scenario('Ship cohorts stay weighted, camouflage reduces firepower and superiority bonuses cap at thirty percent',async()=>{
  await q("update public.planets set race='elys',scouts=0,soldiers=0 where id in($1,$2)",[ps[0].id,ps[1].id]);await grant('ships_elys',10);await q('update public.planets set scouts=10 where id=$1',[ps[0].id]);assert.equal(Number((await q('select ship_tech from public.planets where id=$1',[ps[0].id])).ship_tech),10);
  await grant('ships_elys',20);await q('update public.planets set scouts=scouts+10 where id=$1',[ps[0].id]);assert.equal(Number((await q('select ship_tech from public.planets where id=$1',[ps[0].id])).ship_tech),15);
  await q('update public.planets set scouts=1000 where id=$1',[ps[1].id]);const attacker=await fleet({scouts:1000,shipsLevel:10});await q('select private.resolve_battle($1,now())',[ps[1].id]);assert.equal((await q('select scouts from public.planets where id=$1',[ps[1].id])).scouts,922);assert.equal((await q('select scouts from private.fleets where id=$1',[attacker])).scouts,940);
 });
 await scenario('Camouflage preserves the existing delay, reduces damage and conceals the opposing identity',async()=>{
  await grant('camouflage');await q("update public.planets set race='elys',soldiers=0,scouts=1000 where id=$1",[ps[1].id]);const f=await fleet({scouts:1000});
  await special('camouflage',{fleet_id:f,enabled:true});const delay=(await q('select unavailable_until from private.fleets where id=$1',[f])).unavailable_until;
  await special('camouflage',{fleet_id:f,enabled:false});assert.equal((await q('select unavailable_until from private.fleets where id=$1',[f])).unavailable_until.getTime(),delay.getTime());
  await special('camouflage',{fleet_id:f,enabled:true});await q('select private.resolve_battle($1,now())',[ps[1].id]);
  assert.equal((await q('select scouts from public.planets where id=$1',[ps[1].id])).scouts,955);
  const report=await q("select details from private.battle_reports where empire_id=$1 and event='battle'",[es[1]]);assert.ok(report.details.opponents.every(p=>p.name==='Forces camouflées'));
 });
 await scenario('Stasis charges activation, slows production and preserves its remaining work when lowered',async()=>{
  await grant('stasis');await q("update public.planets set energy=10,captured_at=now()-interval '2 days' where id=$1",[ps[0].id]);const j=await q("insert into private.ship_jobs(empire_id,planet_id,kind,cost,started_at,finishes_at) values($1,$2,'scout',2000,now(),now()+interval '2 hours') returning *",[es[0],ps[0].id]);
  await special('stasis',{planet_id:ps[0].id,enabled:true});assert.equal((await q('select energy from public.planets where id=$1',[ps[0].id])).energy,8);assert.equal(Math.round(((await q('select finishes_at from private.ship_jobs where id=$1',[j.id])).finishes_at-j.started_at)/3600000),6);
  await special('stasis',{planet_id:ps[0].id,enabled:false});assert.equal(Math.round(((await q('select finishes_at from private.ship_jobs where id=$1',[j.id])).finishes_at-j.started_at)/3600000),2);
 });
 await scenario('Transfers preserve cohort levels and camouflage rather than applying current research retroactively',async()=>{
  await grant('ships_elys',3);await grant('armies_elys',4);await q("update public.planets set race='elys',scouts=10,army_tech=4,camouflaged=true,garrison_ready_at='-infinity' where id=$1",[ps[0].id]);
  const created=(await q("select public.military_command('assemble',$1,$2) r",[{planet_id:ps[0].id,name:'Cohorts',scouts:5,bombers:0,fighters:0,soldiers:0},crypto.randomUUID()])).r.id;
  let f=await q('select * from private.fleets where id=$1',[created]);assert.equal(Number(f.ship_tech),3);assert.equal(f.camouflaged,true);
  await grant('ships_elys',20);await q("select public.military_command('disband',$1,$2)",[{fleet_id:created},crypto.randomUUID()]);assert.equal(Number((await q('select ship_tech from public.planets where id=$1',[ps[0].id])).ship_tech),3);
  await q('update public.planets set soldiers=10,army_tech=10 where id=$1',[ps[0].id]);
  const carrier=await q("insert into private.fleets(empire_id,season_id,name,race,supply_planet,planet_id,origin_id,bombers) values($1,$2,'Carrier','elys',$3,$3,$3,2) returning id",[es[0],s,ps[0].id]);
  const ground=await fleet({location:ps[0].id,mission:'defend',scouts:0,ground:5});await q('update private.fleets set army_tech=20 where id=$1',[ground]);
  await q("select public.military_command('load',$1,$2)",[{fleet_id:carrier.id,soldiers:15},crypto.randomUUID()]);f=await q('select * from private.fleets where id=$1',[carrier.id]);assert.ok(Math.abs(Number(f.army_tech)-200/15)<1e-8);
  await q("select public.military_command('load',$1,$2)",[{fleet_id:carrier.id,soldiers:0},crypto.randomUUID()]);assert.ok(Math.abs(Number((await q('select army_tech from public.planets where id=$1',[ps[0].id])).army_tech)-200/15)<1e-8);
 });
 await scenario('Massive bombardment destroys infrastructure and resizes blocked trading capacities consistently',async()=>{
  await q("update public.planets set resource='aurite',trade_capacity=10,soldiers=1000,scouts=0 where id=$1",[ps[1].id]);await q("update public.planets set resource='biomasse',trade_capacity=10 where id=$1",[ps[0].id]);
  await q("select public.trade_command('propose',$1,$2,10,null,$3)",[ps[0].id,ps[1].id,crypto.randomUUID()]);
  const f=await fleet({scouts:1000});await q('update private.fleets set bombers=100,massive_bombing=true where id=$1',[f]);await q('select private.resolve_battle($1,now())',[ps[1].id]);
  const p=await q('select * from public.planets where id=$1',[ps[1].id]);assert.equal(p.population,995000);assert.equal(p.trade_capacity,8);assert.equal(p.factories,4);assert.equal((await q('select private.trade_used($1) n',[p.id])).n,8);
 });
 await scenario('Stargates require the network secret, jump in ten hours and scatter flights if the destination closes',async()=>{
  await grant('stargate');const other=await q('select id from public.planets where owner_empire_id is null limit 1');await q('update public.planets set owner_empire_id=$1 where id=$2',[es[0],other.id]);
  await special('gate_connect',{planet_id:ps[0].id,network:'QA network',password:'NetworkSecret!'});await assert.rejects(special('gate_connect',{planet_id:other.id,network:'QA network',password:'WrongSecret!'}),/refusée/);await special('gate_connect',{planet_id:other.id,network:'QA network',password:'NetworkSecret!'});
  await q("update private.special_projects set gate_ready_at=now()-interval '1 hour' where planet_id in($1,$2)",[ps[0].id,other.id]);const f=await fleet({location:ps[0].id,mission:'defend'});
  await special('gate_jump',{fleet_id:f,target_id:other.id,mission:'defend'});const moving=await q('select * from private.fleets where id=$1',[f]);assert.equal((moving.arrives_at-moving.departed_at)/3600000,10);assert.equal(moving.gate_transit,true);
  await special('gate_disconnect',{planet_id:other.id});assert.notEqual((await q('select destination_id from private.fleets where id=$1',[f])).destination_id,other.id);
  const data=(await q('select private.special_dashboard() d')).d;assert.ok(!JSON.stringify(data).includes('NetworkSecret'));
 });
 await scenario('Black holes obey preparation, annihilate stationed forces and absorb later arrivals',async()=>{
  await grant('black_hole_4');await q("update public.planets set governance='tyrannie',energy=10 where id=$1",[ps[0].id]);await special('black_hole_prepare',{planet_id:ps[0].id,offensive:false});await assert.rejects(special('black_hole_activate',{planet_id:ps[0].id}),/non prêt/);
  await q("update private.special_projects set black_hole_ready_at=now()-interval '1 minute' where planet_id=$1",[ps[0].id]);const victim=await fleet({location:ps[0].id,mission:'defend'});const incoming=await fleet({i:1,location:ps[1].id,mission:'defend'});await q("update private.fleets set status='transit',planet_id=null,destination_id=$1,departed_at=now(),arrives_at=now()+interval '1 hour',route_x=0,route_y=0 where id=$2",[ps[0].id,incoming]);
  await special('black_hole_activate',{planet_id:ps[0].id});const p=await q('select * from public.planets where id=$1',[ps[0].id]);assert.ok(p.destroyed_at);assert.equal(p.population,0);assert.equal(p.factories,0);assert.equal((await q('select status from private.fleets where id=$1',[victim])).status,'destroyed');assert.equal((await q('select count(*) n from private.galaxy_signals() where id=$1',[p.id])).n,0);
  await q("select private.economy_process(now()+interval '2 hours')");assert.equal((await q('select status from private.fleets where id=$1',[incoming])).status,'destroyed');
 });
 await scenario('Offensive confinement warns neighbours and schedules absorption between sixteen and thirty-one days',async()=>{
  await grant('black_hole_offensive');await q("update public.planets set governance='tyrannie',x=0,y=0 where id=$1",[ps[0].id]);await q('update public.planets set x=1,y=1 where id=$1',[ps[1].id]);
  await special('black_hole_prepare',{planet_id:ps[0].id,offensive:true});const z=await q('select * from private.special_projects where planet_id=$1',[ps[0].id]);assert.equal(Math.round((z.black_hole_ready_at-new Date())/3600000),96);
  const targets=(await db.query('select * from private.black_hole_targets where origin_id=$1',[ps[0].id])).rows;assert.ok(targets.length>0);assert.ok(targets.every(p=>p.delay_seconds>=16*86400&&p.delay_seconds<=31*86400));assert.ok((await q("select count(*) n from private.battle_reports where empire_id=$1 and event='black_hole_warning'",[es[1]])).n>0);
  await q("update private.special_projects set black_hole_ready_at=now()-interval '1 minute' where planet_id=$1",[ps[0].id]);await special('black_hole_activate',{planet_id:ps[0].id});assert.ok((await q('select doom_at from private.special_projects where planet_id=$1',[ps[1].id])).doom_at);
  await q("update private.special_projects set doom_at=now()+interval '1 minute' where planet_id=$1",[ps[1].id]);await q("select private.economy_process(now()+interval '2 minutes')");assert.ok((await q('select destroyed_at from public.planets where id=$1',[ps[1].id])).destroyed_at);
 });
 await scenario('Energy blast empties neighbours and cancels ready confinement but leaves preparation intact',async()=>{
  await grant('energy_blast');await q('update public.planets set energy_max=100,energy=100 where id=$1',[ps[0].id]);await q('update public.planets set x=0,y=0 where id=$1',[ps[0].id]);await q("update public.planets set x=1,y=1,energy=10,captured_at=now()-interval '150 days' where id in($1,$2)",[ps[1].id,ps[2].id]);
  await q("insert into private.special_projects(planet_id,black_hole_ready_at) values($1,now()-interval '1 minute'),($2,now()+interval '1 day')",[ps[1].id,ps[2].id]);await special('energy_blast',{planet_id:ps[0].id,energy:40});assert.equal((await q('select energy from public.planets where id=$1',[ps[0].id])).energy,60);assert.equal((await q('select energy from public.planets where id=$1',[ps[1].id])).energy,0);assert.equal((await q('select black_hole_ready_at from private.special_projects where planet_id=$1',[ps[1].id])).black_hole_ready_at,null);assert.ok((await q('select black_hole_ready_at from private.special_projects where planet_id=$1',[ps[2].id])).black_hole_ready_at);assert.equal(Number((await q('select private.fortification(p,now()) n from public.planets p where id=$1',[ps[1].id])).n),.13);
 });
 await scenario('Anonymous clients and outsiders cannot command or read private projects',async()=>{
  await assert.rejects(special('stasis',{planet_id:ps[1].id,enabled:true}),/inaccessible/);
  await db.exec('set role anon');await assert.rejects(tech('research',{planet_id:ps[0].id,technology:'energy'}),/permission/);await assert.rejects(intel('security',{planet_id:ps[0].id,mode:'block'}),/permission/);await assert.rejects(special('energy_blast',{planet_id:ps[0].id,energy:1}),/permission/);await db.exec('reset role');
 });
 }finally{await db.close();}
});

test('Compact research cards and intelligence panels escape names and respect availability',()=>{
 const c={key:'travel',name:'<script>',branch:'infrastructure',effect:'<img>',level:0,max_level:3,next_cost:500000,next_hours:48,requires:[],eligible_planets:[{id:'p',busy:false}],prerequisites_met:true};
 const html=researchTreeView({catalog:[c],planets:[{id:'p',name:'<world>',race:'elys',resource:'aurite'}],research_jobs:[]},500000,'p');assert.doesNotMatch(html,/<script>|<world>|<img>/);assert.match(html,/500.?000/);assert.match(html,/data-technology="research"/);
 assert.doesNotMatch(planetTechnologyModules({id:'p',name:'A',energy:0},{catalog:[],intelligence:{unlocked:false}}),/data-technology="black_hole_activate"/);
});

test('Rollout preserves funded teleportation and already purchased energy reserves',async()=>{
 let user,empire,planet;
 const db=await militaryTestDatabase({beforeMigration:async(db,file)=>{
  if(!file.endsWith('research_tree_and_planet_projects.sql'))return;
  user=crypto.randomUUID();await db.query('insert into auth.users(id) values($1)',[user]);await db.query("select set_config('request.jwt.claim.sub',$1,false)",[user]);
  empire=(await db.query("select public.start_player('QA_Legacy_Tech','Legacy Prime') e")).rows[0].e;planet=(await db.query('select id from public.planets where owner_empire_id=$1',[empire])).rows[0].id;
  await db.query('update public.empires set treasury=100000000 where id=$1',[empire]);
  for(const technology of ['energy','teleport'])await db.query("select public.technology_command('research',$1,$2)",[{technology},crypto.randomUUID()]);
  await db.query("select public.technology_command('energy_capacity',$1,$2)",[{planet_id:planet,quantity:40,expected_capacity:10},crypto.randomUUID()]);
 }});
 try{
  assert.equal((await db.query('select private.teleport_capacity($1) n',[empire])).rows[0].n,5);assert.equal((await db.query('select private.energy_limit($1) n',[empire])).rows[0].n,50);
  const p=(await db.query('select energy_max,energy from public.planets where id=$1',[planet])).rows[0];assert.deepEqual(p,{energy_max:50,energy:10});
 }finally{await db.close();}
});
