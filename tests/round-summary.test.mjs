import test from 'node:test';
import assert from 'node:assert/strict';
import {militaryTestDatabase} from '../scripts/test-military-sql.mjs';
import {roundSummaryView} from '../dist/round-summary.js';
test('Anonymous round summary returns current aggregates without access to player rows',async()=>{
 const db=await militaryTestDatabase();
 try{
  await db.exec('set role anon');
  const data=(await db.query('select public.round_summary() data')).rows[0].data;
  assert.deepEqual(Object.keys(data).sort(),['clans','ends_at','planets','players','round','starts_at']);
  assert.equal(data.round,1);assert.equal(data.players,0);assert.ok(data.planets>=85);assert.equal(data.clans,0);
  await assert.rejects(db.query('select * from public.empires'),/permission denied/);
  await db.exec('reset role');
  const uid=crypto.randomUUID();await db.query('insert into auth.users(id) values($1)',[uid]);await db.query("select set_config('request.jwt.claim.sub',$1,false)",[uid]);
  await db.query("select public.start_player('QA_Round','Round World')");
  await db.exec('set role anon');
  const next=(await db.query('select public.round_summary() data')).rows[0].data;
  assert.equal(next.players,1);assert.equal(next.planets,data.planets+5);
  assert.match(roundSummaryView(next),/Round n°1/);assert.match(roundSummaryView(next),/<time datetime=/);
 }finally{await db.close();}
});
