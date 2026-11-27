// Disposable confirmed QA accounts only, passed via hidden stdin.
import assert from 'node:assert/strict';
import {SUPABASE_URL as url,SUPABASE_KEY as key} from '../dist/config.js';
console.log('Ready for QA JSON on hidden stdin.');
const raw=await new Promise(resolve=>{let text='';const tty=process.stdin.isTTY;if(tty)process.stdin.setRawMode(true);process.stdin.on('data',c=>{text+=c;if(/[\r\n]/.test(text)){if(tty)process.stdin.setRawMode(false);process.stdin.pause();resolve(text.trim());}});process.stdin.resume();});
const accounts=JSON.parse(raw),tokens=[],planets=[];
async function req(path,body,token){const r=await fetch(url+path,{method:body===undefined?'GET':'POST',headers:{apikey:key,'Content-Type':'application/json',...(token?{Authorization:'Bearer '+token}:{})},body:body===undefined?undefined:JSON.stringify(body),signal:AbortSignal.timeout(15000)});return {status:r.status,data:await r.json()};}
async function rpc(i,name,body={}){const r=await req('/rest/v1/rpc/'+name,body,tokens[i]);assert.equal(r.status,200,JSON.stringify(r.data));return r.data;}
for(let i=0;i<2;i++){
 const r=await req('/auth/v1/token?grant_type=password',{email:accounts[i].email,password:accounts[i].password});assert.equal(r.status,200,JSON.stringify(r.data));tokens.push(r.data.access_token);
 await rpc(i,'start_player',{p_username:'QA_Economy_'+(i?'Beta':'Alpha'),p_planet_name:i?'QA Horizon':'QA Origine'});
 planets.push((await req('/rest/v1/planets?select=id',undefined,tokens[i])).data[0].id);
}
const purchase={p_planet_id:planets[0],p_quantity:3,p_expected_capacity:0,p_request_id:crypto.randomUUID()};
const buys=await Promise.all(Array.from({length:3},()=>rpc(0,'purchase_capacities',purchase)));assert.ok(buys.every(x=>x.cost===999&&x.capacity===3));
assert.equal((await rpc(0,'economy_overview')).treasury,99001);
const stale=await req('/rest/v1/rpc/purchase_capacities',{...purchase,p_request_id:crypto.randomUUID()},tokens[0]);assert.notEqual(stale.status,200);assert.match(stale.data.message,/devis a changé/);
await rpc(1,'purchase_capacities',{p_planet_id:planets[1],p_quantity:1,p_expected_capacity:0,p_request_id:crypto.randomUUID()});
await rpc(1,'set_planet_options',{p_planet_id:planets[1],p_clan_tag_visible:false,p_auto_trade:false});
const proposal={p_action:'propose',p_planet_id:planets[0],p_target_id:planets[1],p_quantity:1,p_request_id:crypto.randomUUID()};
const pending=await rpc(0,'trade_command',proposal);assert.equal(pending.status,'pending');assert.deepEqual(await rpc(0,'trade_command',proposal),pending);
assert.equal((await rpc(0,'trade_dashboard',{p_planet_id:planets[0]})).planet.reserved,1);
assert.equal((await rpc(1,'trade_command',{p_action:'accept',p_link_id:pending.link_id,p_request_id:crypto.randomUUID()})).status,'active');
for(let i=0;i<2;i++){const report=await rpc(i,'economy_overview');assert.equal(report.planets.length,1);assert.ok(report.planets[0].trade>report.planets[0].trade_cost);}
const denied=await req('/rest/v1/rpc/trade_dashboard',{p_planet_id:planets[0]},tokens[1]);assert.equal(denied.status,403);
// Keep the active QA-to-QA route for browser inspection; guarded cleanup removes fixtures.
console.log('PASS: REST login, concurrent purchase charged once, stale quote rejected, reservation and replay, manual acceptance, bilateral local revenue, cross-player denial.');
