import test from 'node:test';
import assert from 'node:assert/strict';
import {militaryTestDatabase} from '../scripts/test-military-sql.mjs';
test('Serial industry scales work, instantly buys factories, and paranoia flips stationed outsiders',async()=>{
 const db=await militaryTestDatabase();
 const q=async(s,a=[])=>(await db.query(s,a)).rows[0];
 try{
  const ids=[crypto.randomUUID(),crypto.randomUUID()],es=[],ps=[];
  for(let i=0;i<2;i++){
   await q('insert into auth.users(id) values($1)',[ids[i]]);await q("select set_config('request.jwt.claim.sub',$1,false)",[ids[i]]);
   es.push((await q('select public.start_player($1,$2)e',['QA_Industry_'+i,'Industry '+i])).e);
   ps.push(await q('select * from public.planets where owner_empire_id=$1',[es[i]]));
   await q("update public.planets set resource='aurite' where id=$1",[ps[i].id]);await q('update public.empires set treasury=10000000 where id=$1',[es[i]]);
  }
  await q("select set_config('request.jwt.claim.sub',$1,false)",[ids[0]]);
  const cmd=(action,args,id=crypto.randomUUID())=>q('select public.military_command($1,$2,$3)',[action,args,id]);
  await cmd('ship',{planet_id:ps[0].id,kind:'bomber',quantity:10});
  let span=await q("select count(*)::int n,extract(epoch from(max(finishes_at)-min(started_at)))/3600 hours from private.ship_jobs where planet_id=$1",[ps[0].id]);
  assert.equal(span.n,10);assert.equal(Number(span.hours),80);
  const token=crypto.randomUUID(),args={planet_id:ps[0].id,expected_factories:5};await cmd('factory',args,token);await cmd('factory',args,token);
  assert.equal((await q('select factories from public.planets where id=$1',[ps[0].id])).factories,6);
  await q('update public.planets set factories=10 where id=$1',[ps[0].id]);
  span=await q("select extract(epoch from(max(finishes_at)-min(started_at)))/3600 hours from private.ship_jobs where planet_id=$1",[ps[0].id]);assert.ok(Math.abs(Number(span.hours)-40)<.001);
  await q("insert into private.fleets(empire_id,season_id,name,race,supply_planet,planet_id,origin_id,mission,scouts,ground_soldiers) values($1,$2,'Visitor','elys',$3,$4,$3,'defend',1,5)",[es[1],ps[0].season_id,ps[1].id,ps[0].id]);
  await cmd('paranoid',{planet_id:ps[0].id,enabled:true});
  const f=await q('select mission,unavailable_until>now() na,ground_ready_at>now() ground_na from private.fleets where empire_id=$1',[es[1]]);
  assert.equal(f.mission,'attack');assert.ok(f.na&&f.ground_na);
 }finally{await db.close();}
});
