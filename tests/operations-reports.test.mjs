import test from 'node:test';
import assert from 'node:assert/strict';
import {militaryTestDatabase} from '../scripts/test-military-sql.mjs';
import {forceCamps,militaryOverviewView,commandPlanetOverview} from '../dist/operations.js';
import {battleReportsView,recentBattlesView} from '../dist/reports.js';

test('Overview counts each stationed unit once and distinguishes opposing camps',()=>{
 const p={id:'p',name:'<script>',race:'vael',resource:'aurite',population:1800000,civilization:2,is_own:true,stance:'own',trade_exploited:4,trade_capacity:10,forces:[{is_own:true,kind:'reserve',mission:'defend',scouts:2,ground_soldiers:20},{is_own:true,kind:'fleet',mission:'defend',bombers:1,fighters:1,soldiers:5,ground_soldiers:3,scouts:0},{is_own:false,kind:'fleet',mission:'defend',race:'elys',scouts:3,ground_soldiers:7},{is_own:false,kind:'fleet',mission:'attack',race:'khar',scouts:4,ground_soldiers:9}]};
 const t=forceCamps(p);assert.equal(t.own.soldiers,28);assert.equal(t.own.scouts,2);assert.equal(t.own.fleets,1);assert.equal(t.allies.soldiers,7);assert.equal(t.enemies.scouts,4);
 const data={locations:[p],planets:[{id:'p',factories:5,energy:7,energy_max:15}],jobs:[{planet_id:'p',kind:'scout',finishes_at:'2026-11-10T12:00:00Z'}]};
 const html=militaryOverviewView(data);assert.doesNotMatch(html,/<script>/);assert.match(html,/data-military-location="p"/);assert.match(html,/4 libres/);assert.match(commandPlanetOverview(data),/4 \/ 10/);
 assert.match(html,/force-race.*race_elys\.webp/);assert.match(html,/force-race.*race_khar\.webp/);
 assert.match(commandPlanetOverview(data),/Énergie <b>7 \/ 15/);assert.match(commandPlanetOverview(data),/value="7" max="15" aria-label="Énergie disponible"/);
 const empty={...data,locations:[{...p,forces:p.forces.filter(f=>f.is_own)}]};
 for(const view of [militaryOverviewView(empty),commandPlanetOverview(empty)]){assert.doesNotMatch(view,/overview-force allied|overview-force hostile|force-race/);assert.match(view,/Vos forces/);}

});
test('Reports cap legacy lists at fifteen, recent fights exclude arrivals, unknown losses remain unknown',()=>{
 const reports=Array.from({length:20},(_,i)=>({id:String(i),event:i===0?'arrival':'battle',planet:'A',occurred_at:'2026-11-08T12:00:00Z',details:{before:{soldiers:3},after:{soldiers:2},enemy_ground:null}}));
 const html=battleReportsView({reports});assert.equal((html.match(/<details /g)||[]).length,15);assert.match(html,/Pertes non enregistrées/);assert.match(html,/Forces au sol non observées/);assert.equal((recentBattlesView({reports}).match(/<details /g)||[]).length,5);
 assert.doesNotMatch(html,/Forces alliées/);
 const allies={before:{soldiers:5},after:{soldiers:0}};
 assert.match(battleReportsView({reports:[{...reports[1],details:{...reports[1].details,sides:{allies}}}]}),/Forces alliées/);
 assert.doesNotMatch(battleReportsView({reports:[{...reports[1],details:{...reports[1].details,sides:{allies:{before:{soldiers:0,scouts:0},after:{soldiers:0,scouts:0}}}}}]}),/Forces alliées/);
});
test('Battle snapshots preserve losses across capture; report cursors are isolated and stable',async()=>{
 const db=await militaryTestDatabase();const q=async(s,a=[])=>(await db.query(s,a)).rows[0],users=[crypto.randomUUID(),crypto.randomUUID()],es=[],ps=[];
 try{
 for(let i=0;i<2;i++){await q('insert into auth.users(id) values($1)',[users[i]]);await q("select set_config('request.jwt.claim.sub',$1,false)",[users[i]]);es.push((await q('select public.start_player($1,$2) id',['QA_Dashboard_'+i,'Prime '+i])).id);ps.push(await q('select * from public.planets where owner_empire_id=$1',[es[i]]));}
 await q('update public.planets set soldiers=0,scouts=0,bombers=0,fighters=0 where id=$1',[ps[1].id]);
 await q("insert into private.fleets(empire_id,season_id,name,race,supply_planet,planet_id,origin_id,mission,fighters,ground_soldiers,ground_ready_at) values($1,$2,'Conqueror','elys',$3,$4,$3,'attack',5,10,'-infinity')",[es[0],ps[0].season_id,ps[0].id,ps[1].id]);
 await q('select private.resolve_battle($1,now())',[ps[1].id]);
 const r=await q("select details from private.battle_reports where empire_id=$1 and event='capture'",[es[0]]);assert.equal(r.details.sides.own.after.soldiers,10);assert.equal(r.details.sides.own.before.soldiers,10);assert.equal(r.details.sides.enemies.after.soldiers,0);assert.equal(r.details.sides.allies.before.fighters,0);
 await q("select set_config('request.jwt.claim.sub',$1,false)",[users[0]]);
 await q("insert into private.battle_reports(empire_id,planet_id,event,occurred_at,details) select $1,$2,'battle',now(),'{}' from generate_series(1,31)",[es[0],ps[0].id]);
 const page1=(await q('select public.battle_reports_page() r')).r;assert.equal(page1.items.length,15);assert.equal(typeof page1.next_before,'string');assert.equal(page1.has_more,true);
 await q("insert into private.battle_reports(empire_id,planet_id,event,occurred_at,details) values($1,$2,'arrival',now(),'{}')",[es[0],ps[0].id]);
 const page2=(await q('select public.battle_reports_page($1) r',[page1.next_before])).r;assert.equal(page2.items.length,15);assert.ok(page2.items.every(x=>!page1.items.some(y=>x.id===y.id)));
 const page3=(await q('select public.battle_reports_page($1) r',[page2.next_before])).r;assert.equal(page3.items.length,3);assert.equal(page3.has_more,false);
 const dash=(await q('select public.military_dashboard() r')).r;assert.equal(dash.recent_battles.length,5);assert.ok(dash.recent_battles.every(x=>x.event!=='arrival'));assert.equal(dash.report_page.items.length,15);assert.ok(dash.locations.filter(x=>x.is_own).every(x=>x.trade_capacity!=null));
 await q("select set_config('request.jwt.claim.sub',$1,false)",[users[1]]);const foreign=(await q('select public.battle_reports_page() r')).r;assert.ok(foreign.items.every(x=>!page1.items.some(y=>x.id===y.id)));
 await db.exec('set role anon');await assert.rejects(q('select public.battle_reports_page()'),/permission/);
 }finally{await db.close();}
});
