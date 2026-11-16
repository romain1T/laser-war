import test from 'node:test';
import assert from 'node:assert/strict';
import {militaryTestDatabase} from '../scripts/test-military-sql.mjs';
import {commercialNotificationsView,battleReportsView} from '../dist/military.js';
test('Trade notifications render escaped details without entering the battle renderer',()=>{
 const report={id:'r',event:'trade_created',planet:'<own>',occurred_at:new Date().toISOString(),details:{other_planet:'<other>',quantity:4}};
 const html=commercialNotificationsView({reports:[report]},['r']);assert.ok(html.includes('Nouvelle liaison'));assert.ok(html.includes('is-unread'));assert.ok(html.includes('&lt;other&gt;'));assert.ok(!html.includes('<other>'));assert.ok(battleReportsView({reports:[report]}).includes('Aucun engagement'));
});
test('Another player receives route creation and closure alerts, with durable unread state and no replay duplicates',async()=>{
 const db=await militaryTestDatabase(),q=async(sql,args=[])=>(await db.query(sql,args)).rows[0];const users=['81111111-1111-4111-8111-111111111111','82222222-2222-4222-8222-222222222222'],empires=[],worlds=[];
 const login=async i=>db.query("select set_config('request.jwt.claim.sub',$1,false)",[users[i]]);
 for(let i=0;i<2;i++){await db.query('insert into auth.users(id) values($1)',[users[i]]);await login(i);empires.push((await q('select public.start_player($1,$2) id',['QA_Trade_Alerts_'+i,'Alerts World '+i])).id);worlds.push((await q('select id from public.planets where owner_empire_id=$1',[empires[i]])).id);await db.query('update public.planets set trade_capacity=10,resource=$1 where id=$2',[i?'aurite':'biomasse',worlds[i]]);}
 const command=async(action,id=null,request=crypto.randomUUID())=>(await q('select public.trade_command($1,$2,$3,$4,$5,$6) result',[action,worlds[0],worlds[1],2,id,request])).result;
 await login(0);const request=crypto.randomUUID(),link=(await command('propose',null,request)).link_id;await command('propose',null,request);
 assert.equal((await q('select count(*) n from private.battle_reports where empire_id=$1',[empires[0]])).n,0);assert.equal((await q("select count(*) n from private.battle_reports where empire_id=$1 and event='trade_created'",[empires[1]])).n,1);
 await login(1);let status=(await q('select public.social_status() data')).data;assert.equal(status.alerts.unread,true);await q('select public.social_read($1,$2)',['alerts',status.alerts.latest]);assert.equal((await q('select public.social_status() data')).data.alerts.unread,false);
 await login(0);const cancelRequest=crypto.randomUUID();await command('cancel',link,cancelRequest);await command('cancel',link,cancelRequest);await login(1);status=(await q('select public.social_status() data')).data;assert.equal(status.alerts.unread,true);assert.equal(status.alert_ids.length,1);assert.equal((await q("select count(*) n from private.battle_reports where empire_id=$1 and event='trade_cancelled'",[empires[1]])).n,1);
 // Manual acceptance is another player's action for the original requester.
 await db.query('update public.planets set auto_trade=false where id=$1',[worlds[1]]);await login(0);const pending=(await command('propose')).link_id;assert.equal((await q('select count(*) n from private.battle_reports where empire_id=$1',[empires[0]])).n,0);await login(1);await command('accept',pending);assert.equal((await q("select count(*) n from private.battle_reports where empire_id=$1 and event='trade_created'",[empires[0]])).n,1);
 // A neutral trade partner cannot generate a notification to its initiator.
 await login(0);const neutral=await q("select id from public.planets where owner_empire_id is null and resource<>'biomasse' limit 1");await q("select public.trade_command('propose',$1,$2,1,null,$3)",[worlds[0],neutral.id,crypto.randomUUID()]);assert.equal((await q('select count(*) n from private.battle_reports where empire_id=$1',[empires[0]])).n,1);
 await db.close();
});
