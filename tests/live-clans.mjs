// Run only with two disposable confirmed QA accounts; credentials arrive on hidden stdin.
import assert from 'node:assert/strict';
import { SUPABASE_URL as url, SUPABASE_KEY as key } from '../dist/config.js';
console.log('Ready for two disposable QA accounts JSON on stdin (input is hidden).');
const raw=await new Promise(resolve=>{let text='';const tty=process.stdin.isTTY;if(tty)process.stdin.setRawMode(true);process.stdin.on('data',chunk=>{text+=chunk;if(/[\r\n]/.test(text)){if(tty)process.stdin.setRawMode(false);process.stdin.pause();resolve(text.trim());}});process.stdin.resume();});
const accounts=JSON.parse(raw);const tokens=[];
async function req(path,body,token,method=body===undefined?'GET':'POST'){
  const r=await fetch(url+path,{method,headers:{apikey:key,'Content-Type':'application/json',...(token?{Authorization:'Bearer '+token}:{})},body:body===undefined?undefined:JSON.stringify(body),signal:AbortSignal.timeout(15000)});
  const text=await r.text();let data;try{data=JSON.parse(text);}catch{data=text;}return {status:r.status,data};
}
async function rpc(name,body,token){const r=await req('/rest/v1/rpc/'+name,body,token);assert.equal(r.status,200,JSON.stringify(r.data));return r.data;}
try{
  for(let i=0;i<2;i++){const login=await req('/auth/v1/token?grant_type=password',{email:accounts[i].email,password:accounts[i].password});assert.equal(login.status,200,JSON.stringify(login.data));tokens.push(login.data.access_token);}
  const starts=await Promise.all(Array.from({length:3},()=>rpc('start_player',{p_username:'QA_Clan_Alpha',p_planet_name:'QA Origine'},tokens[0])));assert.equal(new Set(starts).size,1);
  await rpc('start_player',{p_username:'QA_Clan_Beta',p_planet_name:'QA Horizon'},tokens[1]);
  const own=await req('/rest/v1/planets?select=id,name,clan_tag_visible,auto_trade',undefined,tokens[0]);assert.equal(own.data.length,1);const planet=own.data[0];assert.equal(planet.auto_trade,true);assert.equal(planet.clan_tag_visible,false);
  const clanCalls=await Promise.all(Array.from({length:3},()=>rpc('manage_clan',{p_action:'create',p_name:'QA Live Veilleurs'},tokens[0])));assert.equal(new Set(clanCalls).size,1);const clan=clanCalls[0];
  let map=await rpc('galaxy_signals',{},tokens[1]);let signal=map.find(p=>p.id===planet.id);assert.ok(signal.designation.startsWith('Signal '));assert.equal(signal.clan_name,null);assert.deepEqual(Object.keys(signal).sort(),['clan_name','designation','id','is_own','x','y']);
  await rpc('set_planet_options',{p_planet_id:planet.id,p_clan_tag_visible:true,p_auto_trade:false},tokens[0]);map=await rpc('galaxy_signals',{},tokens[1]);signal=map.find(p=>p.id===planet.id);assert.equal(signal.designation,'QA Origine');assert.equal(signal.clan_name,'QA Live Veilleurs');
  const attack=await req('/rest/v1/rpc/set_planet_options',{p_planet_id:planet.id,p_clan_tag_visible:false,p_auto_trade:true},tokens[1]);assert.equal(attack.status,403);
  const direct=await req('/rest/v1/planets?id=eq.'+planet.id,undefined,tokens[1]);assert.deepEqual(direct.data,[]);
  await Promise.all(Array.from({length:3},()=>rpc('manage_clan',{p_action:'join',p_clan_id:clan},tokens[1])));let ownClan=await rpc('my_clan',{},tokens[1]);assert.equal(ownClan.member_count,2);
  await rpc('manage_clan',{p_action:'leave',p_clan_id:clan},tokens[0]);map=await rpc('galaxy_signals',{},tokens[1]);assert.equal(map.find(p=>p.id===planet.id).clan_name,null);ownClan=await rpc('my_clan',{},tokens[1]);assert.equal(ownClan.role,'founder');
  await rpc('manage_clan',{p_action:'leave',p_clan_id:clan},tokens[1]);
  await rpc('set_planet_options',{p_planet_id:planet.id,p_clan_tag_visible:false,p_auto_trade:true},tokens[0]);
  for(const token of tokens)await req('/auth/v1/logout?scope=local',{},token);
  console.log('PASS: actual REST login, concurrent player start/create/join, hidden/public map projection, cross-player access denial, saved trade option, founder succession, tag reset and logout. Disposable accounts remain for UI QA and targeted cleanup.');
}catch(error){console.error('FAIL:',error.message);process.exitCode=1;}
