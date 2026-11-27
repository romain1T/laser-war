import test from 'node:test';
import assert from 'node:assert/strict';
import {militaryTestDatabase} from '../scripts/test-military-sql.mjs';
import {reportCard,reportStatus} from '../dist/reports.js';
import {unitLevel,forceLevelGroups} from '../dist/unit-levels.js';
test('Report outcomes and technology labels distinguish real snapshots and unknown history',()=>{
 assert.equal(reportStatus({event:'capture',details:{captured:true}}),'conquest');assert.equal(reportStatus({event:'capture',details:{mission:'defend'}}),'defeat');
 for(const outcome of ['combat','conquest','victory','defeat'])assert.equal(reportStatus({event:'battle',details:{outcome}}),outcome);
 assert.match(unitLevel(2),/>N2</);assert.match(unitLevel(1.5),/N\? historique/);assert.match(unitLevel(null),/N\?/);
 const html=reportCard({event:'battle',planet:'<Signal>',occurred_at:'2026-11-27T00:00:00Z',details:{outcome:'combat',sides:{own:{before:{scouts:5,units:[{unit:'scouts',race:'elys',level:2,quantity:5}]},after:{scouts:3,units:[{unit:'scouts',race:'elys',level:2,quantity:3}]}}}}});
 assert.match(html,/N2/);assert.match(html,/Combat/);assert.match(html,/−2/);assert.doesNotMatch(html,/<Signal>/);
 assert.equal(forceLevelGroups([{race:'elys',ship_tech:1,scouts:2},{race:'elys',ship_tech:2,scouts:3}],'scouts','elys').length,2);
});
test('A thirteenth conquest succeeds, with private observed technology levels and captured outcomes',async()=>{
 const db=await militaryTestDatabase();const q=async(sql,args=[])=>(await db.query(sql,args)).rows[0];
 try{
 const users=[crypto.randomUUID(),crypto.randomUUID()],empires=[],homes=[];
 for(let i=0;i<2;i++){await q('insert into auth.users(id) values($1)',[users[i]]);await q("select set_config('request.jwt.claim.sub',$1,false)",[users[i]]);empires.push((await q('select public.start_player($1,$2) id',['QA_Reports_'+i,'Report Home '+i])).id);homes.push(await q('select * from public.planets where owner_empire_id=$1',[empires[i]]));}
 await q('update public.planets set owner_empire_id=$1 where id in(select id from public.planets where owner_empire_id is null order by serial limit 11)',[empires[0]]);
 assert.equal(Number((await q('select count(*) n from public.planets where owner_empire_id=$1',[empires[0]])).n),12);
 await q("update public.planets set soldiers=1,scouts=0,bombers=0,fighters=0,garrison_ready_at='-infinity' where id=$1",[homes[1].id]);
 await q("update public.planets set ship_tech=2,army_tech=3 where id=$1",[homes[0].id]);await q("insert into private.research_levels values($1,'ships_elys',2,now()),($1,'armies_elys',3,now())",[empires[0]]);
 await q("insert into private.fleets(empire_id,season_id,name,race,supply_planet,planet_id,origin_id,mission,fighters,ground_soldiers,ground_ready_at) values($1,$2,'Veterans','elys',$3,$4,$3,'attack',5,10000,'-infinity')",[empires[0],homes[0].season_id,homes[0].id,homes[1].id]);
 await q('select private.resolve_battle($1,now())',[homes[1].id]);
 assert.equal((await q('select owner_empire_id from public.planets where id=$1',[homes[1].id])).owner_empire_id,empires[0]);
 assert.equal(Number((await q('select count(*) n from public.planets where owner_empire_id=$1',[empires[0]])).n),13);
 const win=(await q("select details from private.battle_reports where empire_id=$1 and event='capture' order by event_seq desc limit 1",[empires[0]])).details;
 assert.equal(win.outcome,'conquest');assert.ok(win.sides.own.before.units.some(u=>u.unit==='fighters'&&Number(u.level)===2));assert.ok(win.sides.own.before.units.some(u=>u.unit==='soldiers'&&Number(u.level)===3));
 assert.equal((await q("select details->>'outcome' outcome from private.battle_reports where empire_id=$1 and event='capture' order by event_seq desc limit 1",[empires[1]])).outcome,'defeat');
 await q("select set_config('request.jwt.claim.sub',$1,false)",[users[0]]);const dashboard=(await q('select public.military_dashboard() data')).data;
 assert.ok(dashboard.locations.flatMap(p=>p.forces).every(f=>'ship_tech' in f&&'army_tech' in f));
 const leak=JSON.stringify(win.sides);assert.ok(!leak.includes(empires[1]));assert.ok(!leak.includes('empire_id'));
 assert.doesNotMatch((await q("select pg_get_functiondef('private.advance_infiltrations(uuid,timestamptz)'::regprocedure) source")).source,/count\(\*\).*<12/);
 await db.exec('set role anon');await assert.rejects(q('select public.military_dashboard()'),/permission/);
 }finally{await db.close();}
});
