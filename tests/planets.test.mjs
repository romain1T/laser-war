import test from 'node:test';
import assert from 'node:assert/strict';
import {militaryTestDatabase} from '../scripts/test-military-sql.mjs';
import {compactPopulation,planetCapacityQuote} from '../dist/planets.js';
test('Planet population uses compact dot notation and capacity quotes enforce the remaining limit',()=>{
 assert.equal(compactPopulation(1800000),'1.8M');assert.equal(compactPopulation(1000000),'1M');assert.equal(compactPopulation(12500),'12.5K');
 assert.equal(planetCapacityQuote(198,2,{199:59000,200:60000}),119000);assert.equal(planetCapacityQuote(198,3,{}),null);assert.equal(planetCapacityQuote(0,.5,{1:333}),null);
});
test('Planet governance and inline commerce use owner-authorized server commands',async()=>{
 const db=await militaryTestDatabase();const one=async(sql,args=[])=>(await db.query(sql,args)).rows[0];
 const uid='51111111-1111-4111-8111-111111111111',other='52222222-2222-4222-8222-222222222222';await db.query('insert into auth.users(id) values($1),($2)',[uid,other]);
 await db.query("select set_config('request.jwt.claim.sub',$1,false)",[other]);const enemy=(await one("select public.start_player('QA_Planet_Other','Other Planet') id")).id;
 await db.query("select set_config('request.jwt.claim.sub',$1,false)",[uid]);const e=(await one("select public.start_player('QA_Planet_Layout','Test Planet') id")).id;
 const p=await one('select * from public.planets where owner_empire_id=$1',[e]),foreign=await one('select * from public.planets where owner_empire_id=$1',[enemy]);
 await db.query("update public.planets set resource='biomasse',recruitment_fraction=.75 where id=$1",[p.id]);
 const governance=async(mode,expected='conseil',id=crypto.randomUUID(),planet=p.id)=>one('select public.set_governance($1,$2,$3,$4) result',[planet,mode,expected,id]);
 const id=crypto.randomUUID();await governance('tyrannie','conseil',id);await governance('tyrannie','conseil',id);
 const updated=await one('select *,private.recruitment_daily(p) daily from public.planets p where id=$1',[p.id]);assert.equal(updated.governance,'tyrannie');assert.ok(Math.abs(Number(updated.daily)-2.07)<.00001);assert.equal(Number(updated.recruitment_fraction),.75);
 assert.equal((await one('select treasury from public.empires where id=$1',[e])).treasury,150000);
 await assert.rejects(governance('conseil','conseil'),/politique a changé/);await assert.rejects(governance('conseil','tyrannie',id),/déjà utilisé/);await assert.rejects(governance('autre','tyrannie'),/invalide/);await assert.rejects(governance('conseil','conseil',crypto.randomUUID(),foreign.id),/inaccessible/);
 await assert.rejects(governance('conseil','tyrannie'),/Changement politique disponible/);await db.query("update public.planets set governance_changed_at=now()-interval '72 hours' where id=$1",[p.id]);await governance('conseil','tyrannie');const council=await one('select private.recruitment_daily(p) daily from public.planets p where id=$1',[p.id]);assert.ok(Math.abs(Number(council.daily)-1.38)<.00001);
 let overview=(await one('select public.planet_overview() data')).data;assert.equal(overview.planets.length,1);assert.equal(overview.planets[0].id,p.id);assert.equal(overview.prices[1],333);
 await one('select public.purchase_capacities($1,3,0,$2)',[p.id,crypto.randomUUID()]);overview=(await one('select public.planet_overview() data')).data;assert.equal(overview.planets[0].capacity,3);assert.equal(overview.planets[0].available,3);assert.equal(overview.planets[0].used,0);
 assert.equal((await one('select treasury from public.empires where id=$1',[e])).treasury,149001);
 await db.exec('set role authenticated');assert.equal((await one('select public.planet_overview() data')).data.planets.length,1);await assert.rejects(db.query("update public.planets set governance='tyrannie'"),/permission denied/);await db.exec('reset role;set role anon');await assert.rejects(one('select public.planet_overview()'),/permission denied/);await assert.rejects(governance('tyrannie'),/permission denied/);await db.exec('reset role');
 await db.close();
});
