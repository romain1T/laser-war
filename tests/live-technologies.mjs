// Explicitly authorized QA_Tech_Alpha/Beta only. Secrets arrive over hidden stdin.
import assert from 'node:assert/strict';
import {SUPABASE_URL as url,SUPABASE_KEY as key} from '../dist/config.js';
console.log('Ready for technology QA JSON on hidden stdin.');
const raw=await new Promise(resolve=>{let text='';const tty=process.stdin.isTTY;if(tty)process.stdin.setRawMode(true);process.stdin.on('data',chunk=>{text+=chunk;if(/[\r\n]/.test(text)){if(tty)process.stdin.setRawMode(false);process.stdin.pause();resolve(text.trim());}});process.stdin.resume();});
const cfg=JSON.parse(raw),tokens=[];
async function req(i,path,body,method='POST'){const response=await fetch(url+path,{method,headers:{apikey:key,'Content-Type':'application/json',...(tokens[i]?{Authorization:'Bearer '+tokens[i]}:{})},body:body===undefined?undefined:JSON.stringify(body),signal:AbortSignal.timeout(20000)});let data;const text=await response.text();try{data=JSON.parse(text);}catch{data=text;}return {status:response.status,data};}
async function rpc(i,name,args={}){const r=await req(i,'/rest/v1/rpc/'+name,args);assert.ok([200,204].includes(r.status),JSON.stringify(r.data));return r.data;}
const command=(i,action,args,id=crypto.randomUUID())=>rpc(i,'technology_command',{p_action:action,p_args:args,p_request_id:id});
try{
 assert.equal(cfg.accounts.length,2);assert.ok(cfg.run.startsWith('technology-'));
 for(let i=0;i<2;i++){assert.ok(/^qa_tech_[12]\.technology-\d+@example\.invalid$/.test(cfg.accounts[i].email));const login=await req(i,'/auth/v1/token?grant_type=password',{email:cfg.accounts[i].email,password:cfg.password});assert.equal(login.status,200);assert.equal(login.data.user.id,cfg.accounts[i].id);assert.equal(login.data.user.app_metadata.qa_run,cfg.run);tokens[i]=login.data.access_token;}
 let d=await rpc(0,'technology_dashboard');assert.equal(d.energy_unlocked,true);assert.equal(d.teleport_unlocked,true);
 const source=cfg.accounts[0].worlds[0],target=cfg.accounts[1].worlds[0];let p=d.planets.find(p=>p.id===source);
 assert.equal(p.energy_max,11);assert.ok(p.growth.daily_rate>=.0075);assert.ok(!JSON.stringify(d).includes('password_hash'));assert.ok(!JSON.stringify(d).includes(cfg.planetCode));
 const before=p.energy,originTroops=d.origins.find(o=>o.id===source).available_soldiers,request=crypto.randomUUID();
 const args={origin_id:source,target_id:target,quantity:5,password:cfg.planetCode};const result=await command(0,'teleport',args,request);assert.equal(result.energy_cost,1);assert.deepEqual(await command(0,'teleport',args,request),result);
 d=await rpc(0,'technology_dashboard');p=d.planets.find(p=>p.id===source);assert.equal(p.energy,before-1);assert.equal(d.origins.find(o=>o.id===source).available_soldiers,originTroops-5);
 assert.ok(d.origins.some(o=>o.id===target&&o.available_soldiers>=5));
 const clan=await rpc(0,'manage_clan',{p_action:'create',p_name:'QA Technology Test',p_clan_id:null});await rpc(1,'manage_clan',{p_action:'join',p_clan_id:clan,p_name:null});
 assert.equal((await command(0,'teleport',{origin_id:source,target_id:target,quantity:5})).ok,true);
 await rpc(1,'manage_clan',{p_action:'leave',p_clan_id:clan,p_name:null});assert.equal((await command(0,'teleport',{origin_id:source,target_id:target,quantity:1})).ok,false);
 assert.equal((await command(0,'teleport',{origin_id:target,target_id:source,quantity:5,password:cfg.planetCode})).energy_cost,1);
 await rpc(0,'manage_clan',{p_action:'leave',p_clan_id:clan,p_name:null});
 const trade=await rpc(0,'trade_dashboard',{p_planet_id:source});const l=trade.links.find(l=>l.other_id===target);const expected=l.quantity*(1500-Math.min(l.distance,1000))*1.075;assert.ok(Math.abs(Number(l.net_daily)-expected)<.1);
 assert.ok((await req(0,'/rest/v1/rpc/technology_dashboard',{})).status===200);assert.ok((await req(0,'/rest/v1/planets?id=eq.'+target+'&select=*',undefined,'GET')).data.length===0);
 console.log(JSON.stringify({passed:true,checks:['real Auth','both research flags','energy expansion','native bcrypt code','one charge per five','replay conservation','clan access','revoked membership','return from foreign world','commercial 7.5% net uplift','private planet read denial']}));
}catch(error){console.error('FAIL:',error.message);process.exitCode=1;}
