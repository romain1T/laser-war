import test from 'node:test';
import assert from 'node:assert/strict';
import {militaryTestDatabase} from '../scripts/test-military-sql.mjs';
import {militaryDestinations,travelSeconds,militaryView,battleReportsView,assemblyQuote} from '../dist/military.js';
test('Military destinations support nearest fifteen and distant named search',()=>{
 const worlds=Array.from({length:30},(_,i)=>({id:String(i),designation:i===29?'Orion':'Monde '+i,x:i*10,y:0}));
 assert.equal(militaryDestinations(worlds,'0').length,15);assert.equal(militaryDestinations(worlds,'0')[0].id,'1');assert.equal(militaryDestinations(worlds,'0','orion')[0].id,'29');assert.equal(travelSeconds(Math.sqrt(2000000)),604800);
 assert.equal(travelSeconds(0),3600);
});
test('Military interface escapes names and keeps hidden ground forces absent',()=>{
 const html=battleReportsView({reports:[{id:'r',planet:'<img onerror=x>',event:'battle',occurred_at:'2026-11-07T00:00:00Z',details:{mission:'attack',before:{},after:{},enemy_space:{},enemy_ground:null}}]});assert.doesNotMatch(html,/<img onerror/);assert.match(html,/Forces au sol non observées/);
});
test('Assembly transport quotes account for scouts, stock and selected transports',()=>{
 assert.deepEqual(assemblyQuote({scouts:2,bombers:1,fighters:2,soldiers:25},100),{capacity:30,limit:30,remaining:75,valid:true});
 assert.equal(assemblyQuote({scouts:1,bombers:0,fighters:0,soldiers:1},100).valid,false);
 assert.equal(assemblyQuote({scouts:0,bombers:1,fighters:0,soldiers:6},5).valid,false);
 assert.equal(assemblyQuote({scouts:0,bombers:0,fighters:0,soldiers:0},100).valid,false);
 assert.equal(assemblyQuote({scouts:.5,bombers:0,fighters:0,soldiers:0},100),null);
});
test('Authoritative military lifecycle in isolated Postgres',async t=>{
 const db=await militaryTestDatabase();
 let inScenario=false;const rawQuery=db.query.bind(db);
 db.query=async(...args)=>{if(!inScenario)return rawQuery(...args);await db.exec('savepoint test_stmt');try{const result=await rawQuery(...args);await db.exec('release savepoint test_stmt');return result;}catch(error){await db.exec('rollback to savepoint test_stmt;release savepoint test_stmt');throw error;}};
 const one=async(sql,args=[])=>(await db.query(sql,args)).rows[0];
 const uid='11111111-1111-4111-8111-111111111111',uid2='22222222-2222-4222-8222-222222222222';
 await db.query('insert into auth.users(id) values($1),($2)',[uid,uid2]);
 const login=async id=>db.query("select set_config('request.jwt.claim.sub',$1,false)",[id]);
 await login(uid);const e=(await one("select public.start_player('QA_Military_Alpha','Alpha Prime') id")).id;
 await login(uid2);const e2=(await one("select public.start_player('QA_Military_Beta','Beta Prime') id")).id;await login(uid);
 const p=await one('select * from public.planets where owner_empire_id=$1',[e]),p2=await one('select * from public.planets where owner_empire_id=$1',[e2]);
 const command=async(action,args,id=crypto.randomUUID())=>(await one('select public.military_command($1,$2::jsonb,$3) result',[action,JSON.stringify(args),id])).result;
 const dashboard=async()=>(await one('select public.military_dashboard() result')).result;
 const scenario=async(name,fn)=>t.test(name,async()=>{await db.exec('begin');inScenario=true;try{await fn();}finally{inScenario=false;await db.exec('rollback');}});
 await scenario('Assembly embarks troops atomically, conserves units, replays once and rejects invalid loads',async()=>{
  await db.query('update public.planets set scouts=3,bombers=2,fighters=1,soldiers=100 where id=$1',[p.id]);
  const args={planet_id:p.id,name:'Transport',scouts:1,bombers:1,fighters:1,soldiers:17},request=crypto.randomUUID();
  const result=await command('assemble',args,request);assert.deepEqual(await command('assemble',args,request),result);
  let world=await one('select scouts,bombers,fighters,soldiers from public.planets where id=$1',[p.id]);assert.deepEqual(world,{scouts:2,bombers:1,fighters:0,soldiers:83});
  const f=await one('select soldiers,scouts,bombers,fighters from private.fleets where id=$1',[result.id]);assert.deepEqual(f,{soldiers:17,scouts:1,bombers:1,fighters:1});
  await assert.rejects(command('assemble',{...args,soldiers:18},request),/déjà utilisé/);
  const count=(await one('select count(*) n from private.fleets where empire_id=$1',[e])).n;
  await assert.rejects(command('assemble',{...args,fighters:0,bombers:0,soldiers:1}),/Capacité de transport/);
  await assert.rejects(command('assemble',{...args,fighters:0,bombers:1,soldiers:84}),/Soldats disponibles/);
  await assert.rejects(command('assemble',{...args,fighters:0,bombers:1,soldiers:-1}),/Soldats disponibles/);
  assert.deepEqual(await one('select scouts,bombers,fighters,soldiers from public.planets where id=$1',[p.id]),world);assert.equal((await one('select count(*) n from private.fleets where empire_id=$1',[e])).n,count);
  await login(uid2);await assert.rejects(command('assemble',args),/Planète inaccessible/);await login(uid);
  await command('disband',{fleet_id:result.id});assert.deepEqual(await one('select scouts,bombers,fighters,soldiers from public.planets where id=$1',[p.id]),{scouts:3,bombers:2,fighters:1,soldiers:100});
 });
 await scenario('Factory baseline, hourly fractions, stop/start and neutral stasis',async()=>{
  assert.equal(p.factories,5);await db.query("update public.planets set race='elys',resource='aurite',governance='conseil' where id=$1",[p.id]);
  const neutral=await one('select * from public.planets where owner_empire_id is null limit 1');
  await db.exec("select private.economy_process(now()+interval '24 hours')");
  let world=await one('select * from public.planets where id=$1',[p.id]);assert.equal(world.soldiers,101);assert.ok(Number(world.recruitment_fraction)>.2&&Number(world.recruitment_fraction)<.21);assert.ok(world.population>1000000);
  assert.equal((await one('select soldiers from public.planets where id=$1',[neutral.id])).soldiers,1);
  await command('recruitment',{planet_id:p.id,enabled:false});const before=world.soldiers;
  await db.exec("select private.economy_process(now()+interval '48 hours')");world=await one('select * from public.planets where id=$1',[p.id]);assert.equal(world.soldiers,before);
 });
 await scenario('Build completion, Ferros bonus, idempotency and overspending guards',async()=>{
  await db.query("update public.planets set resource='ferros' where id=$1",[p.id]);const id=crypto.randomUUID(),args={planet_id:p.id,kind:'scout',quantity:3};
  await command('ship',args,id);await command('ship',args,id);assert.equal((await dashboard()).jobs.length,3);
  const duration=await one("select extract(epoch from(finishes_at-started_at)) seconds from private.ship_jobs where empire_id=$1 limit 1",[e]);assert.ok(Math.abs(Number(duration.seconds)-7200/1.15)<.01);
  await assert.rejects(command('ship',{...args,quantity:3}),/usines libres/);await assert.rejects(command('ship',{...args,quantity:2},id),/déjà utilisé/);
  await command('factory',{planet_id:p.id,expected_factories:5});await assert.rejects(command('factory',{planet_id:p.id,expected_factories:5}),/déjà en cours/);
  await db.query("update private.ship_jobs set finishes_at=now()-interval '1 minute' where empire_id=$1",[e]);await db.exec('select private.economy_process()');const d=await dashboard();assert.equal(d.planets[0].scouts,3);assert.equal(d.planets[0].factories,6);await assert.rejects(command('factory',{planet_id:p.id,expected_factories:5}),/devis/);
  await db.query('update public.empires set treasury=0 where id=$1',[e]);await assert.rejects(command('ship',{planet_id:p.id,kind:'fighter',quantity:1}),/Trésorerie/);
 });
 await scenario('Units cannot duplicate or overload; owner pays transit upkeep; other players cannot command fleet',async()=>{
  await db.query('update public.planets set scouts=2,bombers=1 where id=$1',[p.id]);const fleet=(await command('assemble',{planet_id:p.id,name:'Transport',scouts:1,bombers:1,fighters:0})).id;
  await command('load',{fleet_id:fleet,soldiers:10});await assert.rejects(command('load',{fleet_id:fleet,soldiers:11}),/Capacité/);
  assert.equal((await one('select soldiers from public.planets where id=$1',[p.id])).soldiers,90);
  await command('dispatch',{fleet_id:fleet,target_id:p2.id,mission:'defend'});await assert.rejects(command('dispatch',{fleet_id:fleet,target_id:p2.id,mission:'defend'}),/indisponible/);
  const overview=(await one('select public.economy_overview() data')).data;const exp=overview.planets.find(p=>p.name==='Forces expéditionnaires');assert.equal(exp.military,20);assert.equal(exp.fleet,80);
  await login(uid2);await assert.rejects(command('disband',{fleet_id:fleet}),/indisponible/);await login(uid);
  const d=await dashboard();assert.equal(d.fleets.length,1);assert.equal(d.planets[0].scouts,1);assert.equal(d.fleets[0].soldiers,10);
 });
 await scenario('Arrival precedes unloading by at least an hour; troops and ships are conserved',async()=>{
  await db.query('update public.planets set bombers=1 where id=$1',[p.id]);const fleet=(await command('assemble',{planet_id:p.id,name:'Secours',scouts:0,bombers:1,fighters:0})).id;
  await command('load',{fleet_id:fleet,soldiers:10});await command('dispatch',{fleet_id:fleet,target_id:p2.id,mission:'defend'});
  await db.query("update private.fleets set arrives_at=date_trunc('hour',now())+interval '10 minutes' where id=$1",[fleet]);
  await db.exec("select private.economy_process(date_trunc('hour',now())+interval '1 hour')");let f=await one('select * from private.fleets where id=$1',[fleet]);assert.equal(f.status,'stationed');assert.equal(f.soldiers,10);assert.equal(f.ground_soldiers,0);
  await assert.rejects(command('load',{fleet_id:fleet,soldiers:0}),/N\/A/);
  await db.exec("select private.economy_process(date_trunc('hour',now())+interval '2 hours')");f=await one('select * from private.fleets where id=$1',[fleet]);assert.equal(f.soldiers,0);assert.equal(f.ground_soldiers,10);assert.equal((await dashboard()).presence[0].soldiers,10);
  await db.query("update private.fleets set unavailable_until=now(),ground_ready_at=now() where id=$1",[fleet]);await command('load',{fleet_id:fleet,soldiers:10});await command('dispatch',{fleet_id:fleet,target_id:p.id,mission:'defend'});f=await one('select * from private.fleets where id=$1',[fleet]);assert.equal(f.soldiers,10);assert.equal(f.ground_soldiers,0);
 });
 await scenario('Combat respects ship roles, hidden ground forces, allied sides and capture',async()=>{
  await db.query("update public.planets set scouts=0,bombers=0,fighters=0,soldiers=1 where id=$1",[p2.id]);
  await db.query('update public.planets set scouts=1,bombers=2,fighters=2 where id=$1',[p.id]);const fleet=(await command('assemble',{planet_id:p.id,name:'Assaut',scouts:0,bombers:2,fighters:2})).id;
  await command('load',{fleet_id:fleet,soldiers:30});await command('dispatch',{fleet_id:fleet,target_id:p2.id,mission:'attack'});
  await db.query("update private.fleets set arrives_at=now()-interval '2 hours' where id=$1",[fleet]);await db.exec('select private.economy_process()');
  await db.query('select private.resolve_battle($1,now())',[p2.id]);let reports=(await dashboard()).reports;assert.equal(reports.find(r=>r.event==='battle').details.enemy_ground,null);
  await db.query('update private.fleets set ground_soldiers=soldiers,soldiers=0 where id=$1',[fleet]);await db.query('select private.resolve_battle($1,now())',[p2.id]);
  const captured=await one('select * from public.planets where id=$1',[p2.id]);assert.equal(captured.owner_empire_id,e);assert.equal(captured.rename_available,true);assert.equal(captured.factories,5);assert.equal(captured.race,p2.race);assert.equal(captured.resource,p2.resource);
  reports=(await dashboard()).reports;assert.ok(reports.some(r=>r.event==='capture'&&r.details.captured));assert.equal((await one('select mission from private.fleets where id=$1',[fleet])).mission,'defend');
  await assert.rejects(command('rename',{planet_id:p2.id}),/invalide/);await command('rename',{planet_id:p2.id,name:'Nouvelle Aube'});await assert.rejects(command('rename',{planet_id:p2.id,name:'Autre nom'}),/indisponible/);
 });
 await scenario('Two defensive players share the same opposing damage and reports',async()=>{
  const third='33333333-3333-4333-8333-333333333333';await db.query('insert into auth.users(id) values($1)',[third]);await login(third);
  const e3=(await one("select public.start_player('QA_Military_Gamma','Gamma Prime') id")).id;await login(uid);
  await db.query("update public.planets set scouts=0,bombers=0,fighters=1,race='elys' where id=$1",[p2.id]);
  const fleet=async(owner,mission,fighters)=>(await one("insert into private.fleets(empire_id,season_id,name,race,supply_planet,planet_id,origin_id,mission,fighters) values($1,$2,'Combined test','elys',$3,$4,$3,$5,$6) returning id",[owner,p.season_id,p.id,p2.id,mission,fighters])).id;
  const friendly=await fleet(e,'defend',1);await fleet(e3,'attack',10);
  for(let i=0;i<3;i++)await db.query('select private.resolve_battle($1,now())',[p2.id]);
  assert.equal((await one('select fighters from public.planets where id=$1',[p2.id])).fighters,0);
  assert.equal((await one('select fighters from private.fleets where id=$1',[friendly])).fighters,0);
  const reports=await db.query('select empire_id,details from private.battle_reports where planet_id=$1',[p2.id]);assert.equal(new Set(reports.rows.map(r=>r.empire_id)).size,3);
  const defenders=reports.rows.filter(r=>r.empire_id===e||r.empire_id===e2);assert.ok(defenders.every(r=>r.details.enemy_space.fighters>0&&r.details.enemy_space.fighters<=10));assert.equal(defenders[0].details.enemy_space.fighters,defenders[1].details.enemy_space.fighters);
 });
 await scenario('RLS and permissions protect units, commands, reports and foreign worlds',async()=>{
  await db.exec('set role authenticated');assert.equal((await db.query('select * from public.planets')).rows.length,1);
  await assert.rejects(db.query('select * from private.fleets'),/permission denied/);await assert.rejects(db.query('select private.military_process()'),/permission denied/);await assert.rejects(db.query('update public.planets set soldiers=999'),/permission denied/);
  const d=await dashboard();assert.ok(d.planets.every(p=>p.owner_empire_id===e));await assert.rejects(command('recruitment',{planet_id:p2.id,enabled:false}),/inaccessible/);await db.exec('reset role');
  await db.exec('set role anon');await assert.rejects(dashboard(),/permission denied/);await db.exec('reset role');
 });
 await db.close();
});
