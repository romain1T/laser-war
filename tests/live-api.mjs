// Optional integration test: supply a disposable, confirmed QA account on stdin.
// Credentials and sessions are kept in memory and are never printed or saved.
import assert from 'node:assert/strict';
import { SUPABASE_URL as url, SUPABASE_KEY as key } from '../dist/config.js';
console.log('Ready for disposable QA account JSON on stdin (input is hidden).');
const raw = await new Promise(resolve=>{
  let text='';const tty=process.stdin.isTTY;if(tty)process.stdin.setRawMode(true);
  process.stdin.on('data',chunk=>{text+=chunk;if(/[\r\n]/.test(text)){if(tty)process.stdin.setRawMode(false);process.stdin.pause();resolve(text.trim());}});process.stdin.resume();
});
const credentials=JSON.parse(raw);
let token;
async function request(path,{method='GET',body,anonymous=false,rawBody=false,headers={}}={}){
  const res=await fetch(url+path,{method,headers:{apikey:key,...(!anonymous&&token?{Authorization:'Bearer '+token}:{}),...(!rawBody?{'Content-Type':'application/json'}:{}),...headers},body:body===undefined?undefined:rawBody?body:JSON.stringify(body),signal:AbortSignal.timeout(15000)});
  const text=await res.text();let data;try{data=JSON.parse(text);}catch{data=text;}return {status:res.status,data};
}
try{
  const login=await request('/auth/v1/token?grant_type=password',{method:'POST',body:{email:credentials.email,password:credentials.password}});
  assert.equal(login.status,200,'Password login');token=login.data.access_token;assert.ok(token);
  const params={p_username:'QA_Commander',p_empire_name:'Empire de vérification',p_planet_name:'Nova QA'};
  const found=await Promise.all(Array.from({length:3},()=>request('/rest/v1/rpc/found_empire',{method:'POST',body:params})));
  found.forEach(r=>assert.equal(r.status,200,JSON.stringify(r.data)));assert.equal(new Set(found.map(r=>r.data)).size,1,'Concurrent founding allocated duplicates');
  const empires=await request('/rest/v1/empires?select=*');assert.equal(empires.status,200);assert.equal(empires.data.length,1);assert.equal(empires.data[0].treasury,100000);
  const planets=await request('/rest/v1/planets?select=*');assert.equal(planets.status,200);assert.equal(planets.data.length,1);assert.equal(planets.data[0].name,'Nova QA');
  const blocked=await request('/rest/v1/empires?id=eq.'+empires.data[0].id,{method:'PATCH',body:{treasury:999999999}});assert.ok([401,403].includes(blocked.status),'Direct treasury write allowed');
  const anon=await request('/rest/v1/planets?select=*',{anonymous:true});assert.ok([401,403].includes(anon.status),'Anonymous planet read allowed');
  const avatarPath=credentials.id+'/avatar.webp';
  const webp=Buffer.from('UklGRiIAAABXRUJQVlA4IBYAAAAwAQCdASoBAAEADsD+JaQAA3AAAAAA','base64');
  const upload=await request('/storage/v1/object/avatars/'+avatarPath,{method:'POST',body:webp,rawBody:true,headers:{'Content-Type':'image/webp','x-upsert':'true'}});assert.equal(upload.status,200,JSON.stringify(upload.data));
  const profile=await request('/rest/v1/profiles?id=eq.'+credentials.id,{method:'PATCH',body:{avatar_path:avatarPath}});assert.ok([200,204].includes(profile.status),JSON.stringify(profile.data));
  const signed=await request('/storage/v1/object/sign/avatars/'+avatarPath,{method:'POST',body:{expiresIn:60}});assert.equal(signed.status,200,JSON.stringify(signed.data));
  const wrongAvatar=await request('/storage/v1/object/avatars/00000000-0000-4000-8000-00000000dead/avatar.webp',{method:'POST',body:webp,rawBody:true,headers:{'Content-Type':'image/webp','x-upsert':'true'}});assert.ok(wrongAvatar.status>=400,'Other player avatar write allowed');
  const remove=await request('/storage/v1/object/avatars',{method:'DELETE',body:{prefixes:[avatarPath]}});assert.equal(remove.status,200,'QA avatar cleanup');
  const logout=await request('/auth/v1/logout',{method:'POST'});assert.ok([200,204].includes(logout.status));
  console.log('PASS: real Auth login/logout, 3 concurrent RPC calls, persistent empire and planet reads, direct-write denial, anonymous denial, private avatar upload/profile/signing, cross-user avatar denial. QA avatar removed.');
}catch(error){console.error('FAIL:',error.message);process.exitCode=1;}
