import test from 'node:test';
import assert from 'node:assert/strict';
import {militaryTestDatabase} from '../scripts/test-military-sql.mjs';
import {tradeView} from '../dist/economy.js';
test('Trade routes show only the target with its art, traits, population and exact capacity blocks',()=>{
 const link={id:'link',other_id:'target',name:'Signal 47',race:'khar',resource:'aurite',population:1800000,civilization:3,appearance:'khar_aurite',quantity:4,available:1,status:'active',distance:382,net_daily:4473};
 const html=tradeView({enabled:true,planet:{id:'own',name:'Marseille Prime',capacity:5,occupied:4,reserved:0},destinations:[],prices:[],links:[link]},[{id:'own',name:'Marseille Prime'}],1000,null);
 const route=html.split('<article class="trade-route">')[1];assert.ok(route);assert.ok(!route.includes('Marseille Prime'));assert.ok(route.includes('khar_aurite.webp'));assert.ok(route.includes('1.8M'));assert.ok(route.includes('Khar'));assert.ok(route.includes('Aurite'));assert.equal((route.match(/engaged unit/g)||[]).length,4);assert.equal((route.match(/free unit/g)||[]).length,1);
});
test('Generated worlds are Signals and trade traits disclose only the linked target',async()=>{
 const db=await militaryTestDatabase();const q=async(sql,args=[])=>(await db.query(sql,args)).rows[0];
 const user='71111111-1111-4111-8111-111111111111';await db.query('insert into auth.users(id) values($1)',[user]);await db.query("select set_config('request.jwt.claim.sub',$1,false)",[user]);const e=(await q("select public.start_player('QA_Trade_Target','Custom Home') id")).id;
 const p=await q('select * from public.planets where owner_empire_id=$1',[e]),target=await q('select * from public.planets where owner_empire_id is null limit 1');assert.equal(target.name,'Signal '+target.serial);assert.equal(p.name,'Custom Home');
 await db.query("update public.planets set resource='biomasse',trade_capacity=5 where id=$1",[p.id]);await db.query("update public.planets set race='khar',resource='aurite' where id=$1",[target.id]);
 await q('select public.trade_command($1,$2,$3,$4,$5,$6)', ['propose',p.id,target.id,4,null,crypto.randomUUID()]);
 const d=(await q('select public.trade_dashboard($1) data',[p.id])).data;const l=d.links.find(l=>l.other_id===target.id);assert.equal(l.race,'khar');assert.equal(l.population,1000000);assert.equal(l.appearance,'khar_aurite');assert.equal(l.name,'Signal '+target.serial);assert.ok(!('owner_empire_id' in l));assert.ok(!d.destinations.some(w=>w.name.startsWith('Terra_Nullius')));
 await db.query("update public.planets set name='Terra_Nullius_'||serial where id=$1",[target.id]);assert.equal((await q('select name from public.planets where id=$1',[target.id])).name,'Signal '+target.serial);
 await db.close();
});
