import test from 'node:test';
import assert from 'node:assert/strict';
import {militaryTestDatabase} from '../scripts/test-military-sql.mjs';
import {reportCard} from '../dist/reports.js';

test('Two Khar scouts eliminate a neutral Vael scout within two hourly rounds',async()=>{
 const db=await militaryTestDatabase();
 try {
  const uid=crypto.randomUUID();
  await db.query('insert into auth.users(id) values($1)',[uid]);
  await db.query("select set_config('request.jwt.claim.sub',$1,false)",[uid]);
  const e=(await db.query("select public.start_player('QA_Pacing','Pacing') e")).rows[0].e;
  const home=(await db.query('select * from public.planets where owner_empire_id=$1',[e])).rows[0];
  const target=(await db.query('select * from public.planets where owner_empire_id is null limit 1')).rows[0];
  await db.query("update public.planets set race='vael' where id=$1",[target.id]);
  await db.query("insert into private.fleets(empire_id,season_id,name,race,supply_planet,planet_id,origin_id,mission,scouts,bombers) values($1,$2,'SG-1','khar',$3,$4,$3,'attack',2,1)",[e,home.season_id,home.id,target.id]);
  await db.query('select private.resolve_battle($1,now())',[target.id]);
  assert.equal((await db.query('select scouts from public.planets where id=$1',[target.id])).rows[0].scouts,1);
  await db.query("select private.resolve_battle($1,now()+interval '1 hour')",[target.id]);
  const p=(await db.query('select scouts,owner_empire_id from public.planets where id=$1',[target.id])).rows[0];
  assert.equal(p.scouts,0);
  assert.equal(p.owner_empire_id,null,'No capture without ground troops');
 } finally {await db.close();}
});

test('Reports highlight actual losses and leave zero-loss cells neutral',()=>{
 const before={soldiers:100,scouts:2,bombers:1,fighters:0},after={...before,soldiers:90};
 const html=reportCard({event:'battle',planet:'Signal 329',occurred_at:'2026-11-10T00:00:00Z',details:{sides:{own:{before,after}}}});
 assert.match(html,/loss-hit[^>]*>−10/);
 assert.match(html,/remaining-hit[^>]*>90/);
 assert.match(html,/survivants/);
 assert.match(html,/casualty ">0/);
 assert.doesNotMatch(html,/Forces alliées/);
});
