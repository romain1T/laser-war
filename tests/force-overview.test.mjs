import test from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {militaryTestDatabase} from '../scripts/test-military-sql.mjs';
import {militaryView,militaryCommandView,transitView} from '../dist/military.js';
import {shipArt} from '../dist/art.js';

test('Every supplied ship has a bounded race/type mapping and an optimized asset',async()=>{
 for(const race of ['elys','khar','vael'])for(const [kind,file] of [['scout','scout'],['bomber','bombardier'],['fighter','destroyer']]){
  assert.match(shipArt(race,kind),new RegExp(race+'_'+file+'\\.webp'));assert.ok((await readFile(`dist/assets/art/${race}_${file}.webp`)).length>1000);
 }
 assert.equal(shipArt('elys','../escape'),'');assert.doesNotMatch(shipArt('../escape','scout'),/escape/);
});

test('Stationed fleet totals and foreign force visibility are authorized by physical presence',async t=>{
 const db=await militaryTestDatabase(),q=async(s,a=[])=>(await db.query(s,a)).rows[0],users=['11111111-1111-4111-8111-111111111111','22222222-2222-4222-8222-222222222222','33333333-3333-4333-8333-333333333333'],es=[],ps=[];
 const login=i=>q("select set_config('request.jwt.claim.sub',$1,false)",[users[i]]);
 for(let i=0;i<3;i++){await q('insert into auth.users(id) values($1)',[users[i]]);await login(i);es.push((await q('select public.start_player($1,$2) id',['QA_Force_'+i,'Prime '+i])).id);ps.push(await q('select * from public.planets where owner_empire_id=$1',[es[i]]));}
 await login(0);const s=ps[0].season_id;
 const fleet=async(owner,p,mission,scouts,bombers,fighters,ground,cargo=0)=>(await q("insert into private.fleets(empire_id,season_id,name,race,supply_planet,planet_id,origin_id,mission,scouts,bombers,fighters,ground_soldiers,soldiers) values($1,$2,$3,'khar',$4,$5,$4,$6,$7,$8,$9,$10,$11) returning id",[es[owner],s,'Force '+owner,ps[owner].id,p,mission,scouts,bombers,fighters,ground,cargo])).id;
 const view=async()=>(await q('select public.military_dashboard() r')).r;
 const scenario=(name,run)=>t.test(name,async()=>{await db.exec('begin');try{await run();}finally{await db.exec('rollback');}});
 await scenario('Totals include reserves, stationed ships, ground and embarked troops once, excluding transit and foreign units',async()=>{
  await q('update public.planets set scouts=3,bombers=2,fighters=1,soldiers=100 where id=$1',[ps[0].id]);
  await fleet(0,ps[0].id,'defend',4,2,3,7,9);await fleet(0,ps[0].id,'defend',1,0,0,5);await fleet(1,ps[0].id,'defend',90,0,0,80);
  const moving=await fleet(0,ps[0].id,'defend',40,0,0,0);await q("update private.fleets set status='transit',planet_id=null,destination_id=$2,departed_at=now(),arrives_at=now()+interval '1 day' where id=$1",[moving,ps[2].id]);
  const d=await view(),p=d.locations.find(x=>x.id===ps[0].id);assert.deepEqual(p.own_totals,{fleets:2,scouts:8,bombers:4,fighters:4,soldiers:121,ground:112,embarked:9,ships:16});assert.equal(p.defense.scouts,98);assert.equal(d.locations.some(x=>x.id===ps[2].id),false);
  const before=p.own_totals;await q('select public.military_command($1,$2,$3)',['assemble',{planet_id:ps[0].id,name:'SG-3',scouts:1,bombers:1,fighters:0,soldiers:5},crypto.randomUUID()]);const after=(await view()).locations.find(x=>x.id===ps[0].id).own_totals;
  for(const k of ['scouts','bombers','fighters','soldiers','ships'])assert.equal(after[k],before[k]);assert.equal(after.fleets,3);
 });
 await scenario('Only owned or physically occupied worlds expose foreign fleets, with no player identity or remote route fields',async()=>{
  await fleet(0,ps[1].id,'defend',2,1,0,8,5);await fleet(2,ps[1].id,'attack',3,0,1,9);await fleet(0,ps[2].id,'attack',1,0,0,0);
  const neutral=await q('select id from public.planets where owner_empire_id is null limit 1');await fleet(2,neutral.id,'attack',999,0,0,0);
  const d=await view(),b=d.locations.find(x=>x.id===ps[1].id),c=d.locations.find(x=>x.id===ps[2].id);assert.equal(b.stance,'defend');assert.equal(c.stance,'attack');assert.equal(d.locations.some(x=>x.id===neutral.id),false);assert.equal(d.planets.length,1);
  assert.equal(b.attack.ships,4);assert.equal(b.forces.filter(x=>!x.is_own).length,2);
  for(const f of b.forces){for(const key of ['id','empire_id','owner_empire_id','player_id','origin_id','supply_planet','destination_id'])assert.equal(key in f,false);}
  const foreignView=militaryView(d,b.id);assert.match(foreignView,/Forces étrangères/);assert.match(foreignView,/Prime 1 · En défense/);assert.doesNotMatch(foreignView,/data-military="(?:ship|assemble|factory|recruitment|paranoid)"/);assert.match(foreignView,/khar_scout\.webp/);assert.doesNotMatch(foreignView,/ship-cockpit|◇/);
  const ownView=militaryView(d,ps[0].id);assert.match(ownView,/TOTAL DE VOS FORCES PRÉSENTES/);assert.doesNotMatch(ownView,/data-mission-fleet/);
  assert.match(militaryCommandView(d),/Positions extérieures/);assert.match(militaryCommandView(d),/data-military-location/);
  await q("update private.fleets set status='disbanded' where empire_id=$1 and planet_id=$2",[es[0],ps[1].id]);assert.equal((await view()).locations.some(x=>x.id===ps[1].id),false);
 });
 await scenario('Mixed own missions use the attack warning and transit endpoints include planet art',async()=>{
  await fleet(0,ps[1].id,'attack',1,0,0,0);await fleet(0,ps[1].id,'defend',2,0,0,0);const id=await fleet(0,ps[0].id,'defend',1,0,0,0);
  await q("update private.fleets set status='transit',planet_id=null,destination_id=$2,departed_at=now(),arrives_at=now()+interval '1 day' where id=$1",[id,ps[1].id]);
  const d=await view();assert.equal(d.locations.find(x=>x.id===ps[1].id).stance,'mixed');const moving=d.fleets.find(f=>f.id===id);assert.equal(moving.origin_appearance,ps[0].race+'_'+ps[0].resource);assert.equal(moving.destination_appearance,ps[1].race+'_'+ps[1].resource);assert.equal((transitView(d).match(/class="route-endpoint"/g)||[]).length,2);
 });
 await scenario('The location projection and aggregate helper cannot be invoked anonymously or read as raw tables',async()=>{
  await q("select set_config('request.jwt.claim.sub','',false)");await db.exec('savepoint auth');await assert.rejects(view(),/Connexion|Connectez|Session|Joueur|participation/i);await db.exec('rollback to savepoint auth');
  assert.equal((await q("select has_function_privilege('authenticated','private.force_totals(jsonb,boolean,text)','execute') allowed")).allowed,false);
  assert.equal((await q("select has_function_privilege('authenticated','private.military_dashboard_base()','execute') allowed")).allowed,false);
 });
 await db.close();
});
