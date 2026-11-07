import test from 'node:test';
import assert from 'node:assert/strict';
import {militaryTestDatabase} from '../scripts/test-military-sql.mjs';
import {energyQuote,teleportDestinations,teleportQuote,technologiesView} from '../dist/technologies.js';
test('Energy quotes, troop teleport pricing and nearest destinations remain bounded',()=>{
 assert.equal(energyQuote(98,2,{99:10,100:20}),30);assert.equal(energyQuote(99,2,{}),null);
 const origin={id:'o',name:'Home',is_own:true,x:0,y:0,energy:10,available_soldiers:100,network_ready_at:'2020-01-01'};
 const targets=Array.from({length:30},(_,i)=>({id:String(i),name:'Signal '+i,is_own:i%2===0,x:i,y:0,access:i%2?'password':'own',energy:10,network_ready_at:'2020-01-01'}));
 assert.equal(teleportDestinations(targets,origin).length,15);assert.equal(teleportDestinations(targets,origin,'Signal 29')[0].id,'29');
 assert.equal(teleportQuote(origin,targets[0],9).cost,1);assert.equal(teleportQuote(origin,targets[1],9).cost,2);assert.equal(teleportQuote(origin,targets[1],51).valid,false);
 assert.equal(teleportQuote(origin,targets[1],1).needsPassword,true);assert.equal(teleportDestinations(targets,{...origin,is_own:false}).some(p=>!p.is_own),false);
});
test('Technologies, regeneration, demography and teleportation have authoritative conserved state',async t=>{
 const db=await militaryTestDatabase();let inScenario=false;const raw=db.query.bind(db);db.query=async(...args)=>{if(!inScenario)return raw(...args);await db.exec('savepoint statement');try{const result=await raw(...args);await db.exec('release savepoint statement');return result;}catch(error){await db.exec('rollback to savepoint statement;release savepoint statement');throw error;}};
 const q=async(sql,args=[])=>(await db.query(sql,args)).rows[0],uids=['91111111-1111-4111-8111-111111111111','92222222-2222-4222-8222-222222222222'],es=[],ps=[];
 const login=async i=>db.query("select set_config('request.jwt.claim.sub',$1,false)",[uids[i]]);
 for(let i=0;i<2;i++){await db.query('insert into auth.users(id) values($1)',[uids[i]]);await login(i);es.push((await q('select public.start_player($1,$2) id',['QA_Tech_'+i,'Tech World '+i])).id);ps.push((await q('select * from public.planets where owner_empire_id=$1',[es[i]])).id);await db.query('update public.empires set treasury=2000000 where id=$1',[es[i]]);}
 await login(0);const season=(await q('select season_id from public.empires where id=$1',[es[0]])).season_id;
 const cmd=async(action,args,id=crypto.randomUUID())=>(await q('select public.technology_command($1,$2::jsonb,$3) result',[action,JSON.stringify(args),id])).result;
 const dash=async()=>(await q('select public.technology_dashboard() data')).data;
 const scenario=async(name,fn)=>t.test(name,async()=>{await db.exec('begin');inScenario=true;try{await fn();}finally{inScenario=false;await db.exec('rollback');}});
 await scenario('Research costs are charged once; energy starts full at ten and expands without free charges',async()=>{
  const request=crypto.randomUUID();await cmd('research',{technology:'energy'},request);await cmd('research',{technology:'energy'},request);assert.equal((await q('select treasury from public.empires where id=$1',[es[0]])).treasury,1850000);
  let p=await q('select energy,energy_max from public.planets where id=$1',[ps[0]]);assert.deepEqual(p,{energy:10,energy_max:10});await cmd('research',{technology:'teleport'});assert.equal((await q('select treasury from public.empires where id=$1',[es[0]])).treasury,1550000);
  await cmd('energy_capacity',{planet_id:ps[0],quantity:1,expected_capacity:10});p=await q('select energy,energy_max from public.planets where id=$1',[ps[0]]);assert.deepEqual(p,{energy:10,energy_max:11});
  await assert.rejects(cmd('energy_capacity',{planet_id:ps[0],quantity:1,expected_capacity:10}),/devis énergétique/);await assert.rejects(cmd('energy_capacity',{planet_id:ps[1],quantity:1,expected_capacity:10}),/inaccessible/);
  await q("select private.advance_planet_development($1,now()+interval '6 hours')",[season]);assert.equal((await q('select energy from public.planets where id=$1',[ps[0]])).energy,11);
  await q("select private.advance_planet_development($1,now()+interval '48 hours')",[season]);assert.equal(Number((await q('select energy_fraction from public.planets where id=$1',[ps[0]])).energy_fraction),0);
 });
 await scenario('Demography rewards Council and occupied commerce, is reduced by nearby wars and stops on the planet',async()=>{
  await db.query("update public.planets set governance='conseil',population=1000000,trade_capacity=10,resource='biomasse',development_last_at=now() where id=$1",[ps[0]]);
  await db.query("update public.planets set resource='aurite',trade_capacity=10 where id=$1",[ps[1]]);
  assert.equal(Number((await q('select private.population_growth_state($1) g',[ps[0]])).g.daily_rate),.006);
  await q("select public.trade_command('propose',$1,$2,5,null,$3)",[ps[0],ps[1],crypto.randomUUID()]);assert.equal(Number((await q('select private.population_growth_state($1) g',[ps[0]])).g.daily_rate),.00675);
  await q("select private.advance_planet_development($1,now()+interval '24 hours')",[season]);assert.equal((await q('select population from public.planets where id=$1',[ps[0]])).population,1006750);
  const neutral=await q('select * from public.planets where owner_empire_id is null limit 1');assert.equal(neutral.population,1000000);
  await db.query('update public.planets set x=1000,y=1000 where season_id=$1',[season]);await db.query('update public.planets set x=0,y=0 where id=$1',[ps[0]]);await db.query('update public.planets set x=1,y=1 where id=$1',[neutral.id]);
  await db.query("insert into private.fleets(empire_id,season_id,name,race,supply_planet,planet_id,origin_id,mission,scouts) values($1,$2,'War','khar',$3,$4,$3,'attack',1)",[es[1],season,ps[1],neutral.id]);assert.equal(Number((await q('select private.population_growth_state($1) g',[ps[0]])).g.daily_rate),.003375);
  await db.query('update private.fleets set planet_id=$1 where name=\'War\'',[ps[0]]);assert.equal(Number((await q('select private.population_growth_state($1) g',[ps[0]])).g.daily_rate),0);
 });
 await scenario('Own-world teleport moves only soldiers instantly, uses half-price energy and cannot duplicate a replay',async()=>{
  await cmd('research',{technology:'energy'});await cmd('research',{technology:'teleport'});
  const target=await q('select id from public.planets where owner_empire_id is null limit 1');await db.query('update public.planets set owner_empire_id=$1,teleport_ready_at=now() where id=$2',[es[0],target.id]);
  // Capture correctly installs a connection delay; a trusted test advances it.
  assert.ok(new Date((await q('select teleport_ready_at from public.planets where id=$1',[target.id])).teleport_ready_at)>new Date());await db.query("update public.planets set teleport_ready_at=now()-interval '1 second' where id=$1",[target.id]);
  const args={origin_id:ps[0],target_id:target.id,quantity:9},id=crypto.randomUUID();await cmd('teleport',args,id);await cmd('teleport',args,id);
  assert.deepEqual(await q('select soldiers,energy,scouts,bombers,fighters from public.planets where id=$1',[ps[0]]),{soldiers:91,energy:9,scouts:0,bombers:0,fighters:0});assert.equal((await q('select sum(ground_soldiers) n from private.fleets where empire_id=$1 and planet_id=$2',[es[0],target.id])).n,9);
  await assert.rejects(cmd('teleport',{...args,quantity:10},id),/déjà utilisé/);assert.equal((await q('select count(*) n from private.battle_reports where empire_id=$1',[es[0]])).n,1);
 });
 await scenario('Foreign teleports require both technologies and current clan membership or a valid private code',async()=>{
  await cmd('research',{technology:'energy'});await cmd('research',{technology:'teleport'});
  await assert.rejects(cmd('teleport',{origin_id:ps[0],target_id:ps[1],quantity:1}),/deux propriétaires/);
  await login(1);await cmd('research',{technology:'teleport'});await cmd('password',{planet_id:ps[1],password:'TestCode!1234'});await login(0);
  let result=await cmd('teleport',{origin_id:ps[0],target_id:ps[1],quantity:2,password:'incorrect'});assert.equal(result.ok,false);assert.equal((await q('select energy from public.planets where id=$1',[ps[0]])).energy,10);assert.equal((await q('select count(*) n from private.teleport_attempts where empire_id=$1',[es[0]])).n,1);
  result=await cmd('teleport',{origin_id:ps[0],target_id:ps[1],quantity:2,password:'TestCode!1234'});assert.equal(result.energy_cost,1);assert.equal((await q('select sum(ground_soldiers) n from private.fleets where empire_id=$1 and planet_id=$2',[es[0],ps[1]])).n,2);
  assert.ok(!JSON.stringify(await dash()).includes('TestCode'));assert.ok(!JSON.stringify(await dash()).includes('password_hash'));
  const clan=(await q("select public.manage_clan('create',null,'Tech Clan') id")).id;await login(1);await q("select public.manage_clan('join',$1,null)",[clan]);await login(0);assert.equal((await cmd('teleport',{origin_id:ps[0],target_id:ps[1],quantity:1})).ok,true);
  await db.query('update public.planets set owner_empire_id=$1 where id=$2',[es[0],ps[1]]);assert.equal((await q('select count(*) n from private.planet_teleport_access where planet_id=$1',[ps[1]])).n,0);
 });
 await scenario('Technology data and password hashes remain inaccessible across users and to anonymous clients',async()=>{
  await db.exec('set role authenticated');await assert.rejects(q('select * from private.planet_teleport_access'),/permission denied/);await assert.rejects(q('select * from private.player_technologies'),/permission denied/);assert.equal((await dash()).planets.length,1);await db.exec('reset role;set role anon');await assert.rejects(dash(),/permission denied/);await assert.rejects(cmd('research',{technology:'energy'}),/permission denied/);await db.exec('reset role');
 });
 await db.close();
});
