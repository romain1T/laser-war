import test from 'node:test';
import assert from 'node:assert/strict';
import {militaryTestDatabase} from '../scripts/test-military-sql.mjs';
import {forceLevelGroups} from '../dist/unit-levels.js';
import {technologyNotificationsView} from '../dist/technology-actions.js';
test('Research notifications retain five latest technologies and emphasize their names',()=>{
 const reports=Array.from({length:8},(_,i)=>({id:String(i),event:'research_complete',planet:'Prime',occurred_at:`2026-11-${String(i+10).padStart(2,'0')}T00:00:00Z`,details:{message:'Tech '+i}}));
 const html=technologyNotificationsView({reports});assert.equal((html.match(/class="document-panel/g)||[]).length,5);assert.doesNotMatch(html,/Tech 0|Tech 1|Tech 2/);assert.match(html,/<h3>Tech 7<\/h3>/);assert.match(html,/Recherche terminée · Prime/);
 const groups=forceLevelGroups([{race:'vael',scouts:8,unit_cohorts:{scouts:{0:3,1:5}}}],'scouts','vael');assert.deepEqual(groups.map(g=>[g.level,g.quantity]),[[0,3],[1,5]]);
});
test('Exact cohorts conserve integer counts through assembly, cargo transfers, disband, TP and losses',async()=>{
 const db=await militaryTestDatabase(),q=async(sql,args=[])=>(await db.query(sql,args)).rows[0];
 try{
 const uid=crypto.randomUUID();await q('insert into auth.users(id) values($1)',[uid]);await q("select set_config('request.jwt.claim.sub',$1,false)",[uid]);const e=(await q("select public.start_player('QA_Cohorts','Cohort Prime') id")).id,p=await q('select * from public.planets where owner_empire_id=$1',[e]);
 await q('update public.planets set soldiers=0,bombers=0,scouts=0,fighters=0 where id=$1',[p.id]);
 await q('update public.planets set soldiers=100,bombers=2 where id=$1',[p.id]);
 await q('insert into private.research_levels values($1,$2,1,now()),($1,$3,1,now())',[e,'ships_'+p.race,'armies_'+p.race]);await q('update public.planets set soldiers=200,bombers=4 where id=$1',[p.id]);
 const check=async()=>{const x=await q('select unit_cohorts from public.planets where id=$1',[p.id]);assert.equal(x.unit_cohorts.soldiers['0'],100);assert.equal(x.unit_cohorts.soldiers['1'],100);assert.equal(x.unit_cohorts.bombers['0'],2);assert.equal(x.unit_cohorts.bombers['1'],2);};await check();
 const cmd=async(action,args)=>(await q('select public.military_command($1,$2,$3) r',[action,args,crypto.randomUUID()])).r;
 const f=(await cmd('assemble',{planet_id:p.id,name:'Mixed',scouts:0,bombers:2,fighters:0,soldiers:20})).id;
 let x=await q('select unit_cohorts from private.fleets where id=$1',[f]);assert.equal(x.unit_cohorts.bombers['0'],1);assert.equal(x.unit_cohorts.bombers['1'],1);assert.equal(x.unit_cohorts.soldiers['0'],10);assert.equal(x.unit_cohorts.soldiers['1'],10);
 await cmd('load',{fleet_id:f,soldiers:0});await cmd('disband',{fleet_id:f});await check();
 await q("insert into private.player_technologies(empire_id,energy_unlocked_at,teleport_unlocked_at) values($1,now(),now()) on conflict(empire_id) do update set energy_unlocked_at=now(),teleport_unlocked_at=now()",[e]);await q("insert into private.research_levels values($1,'energy',1,now()),($1,'teleport',1,now())",[e]);
 const t=await q('select * from public.planets where owner_empire_id is null limit 1');await q("update public.planets set owner_empire_id=$1,teleport_ready_at='-infinity',soldiers=0 where id=$2",[e,t.id]);await q("update public.planets set energy=100,energy_max=100,teleport_ready_at='-infinity',garrison_ready_at='-infinity' where id=$1",[p.id]);
 await q("update public.planets set teleport_ready_at='-infinity' where id=$1",[t.id]);await q('select public.technology_command($1,$2,$3)', ['teleport',{origin_id:p.id,target_id:t.id,quantity:20},crypto.randomUUID()]);
 const tele=await q("select unit_cohorts from private.fleets where planet_id=$1 and name='Renforts téléportés' limit 1",[t.id]);assert.equal(tele.unit_cohorts.soldiers['0'],10);assert.equal(tele.unit_cohorts.soldiers['1'],10);
 // Losses remove an integer proportional share, never all veterans first.
 await q('update public.planets set soldiers=soldiers-3 where id=$1',[p.id]);x=await q('select soldiers,unit_cohorts from public.planets where id=$1',[p.id]);assert.equal(Object.values(x.unit_cohorts.soldiers).reduce((a,b)=>a+b,0),x.soldiers);assert.ok(Math.abs(x.unit_cohorts.soldiers['0']-x.unit_cohorts.soldiers['1'])<=1);
 const r=await q("select private.report_force_totals($1,$2,'defend','own') data",[[{empire_id:e,side:'defend',race:p.race,scouts:0,bombers:0,fighters:0,ground:10,cargo:0,unit_cohorts:{soldiers:{0:4,1:6}}}],e]);assert.equal(r.data.units.length,2);
 const before=(await q('select public.social_status() r')).r;await q('select public.social_read($1,$2)', ['alerts',before.alerts.latest]);
 await q("insert into private.battle_reports(empire_id,planet_id,occurred_at,event,details) values($1,$2,now(),'battle','{}')",[e,p.id]);assert.equal((await q('select public.social_status() r')).r.combat_unread,true);
 const st=(await q('select public.social_status() r')).r;await q('select public.social_read($1,$2)',['alerts',st.alerts.latest]);assert.equal((await q('select public.social_status() r')).r.combat_unread,false);
 await q("insert into private.battle_reports(empire_id,planet_id,occurred_at,event,details) select $1,$2,now(),'research_complete',jsonb_build_object('message','Tech '||i) from generate_series(1,8)i",[e,p.id]);await q("insert into private.battle_reports(empire_id,planet_id,occurred_at,event,details) select $1,$2,now(),'battle','{}' from generate_series(1,55)",[e,p.id]);
 assert.equal((await q('select public.military_dashboard() r')).r.research_notifications.length,5);
 }finally{await db.close();}
});
