// Opt-in live verification. Only explicitly authorized, disposable social QA users.
// Credentials arrive over hidden stdin, never arguments, files, logs or source.
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {SUPABASE_URL as url,SUPABASE_KEY as key} from '../dist/config.js';
console.log('Ready for social QA fixture JSON on stdin (input is hidden).');
const raw=await new Promise(resolve=>{let text='';const tty=process.stdin.isTTY;if(tty)process.stdin.setRawMode(true);process.stdin.on('data',chunk=>{text+=chunk;if(/[\r\n]/.test(text)){if(tty)process.stdin.setRawMode(false);process.stdin.pause();resolve(text.trim());}});process.stdin.resume();});
const cfg=JSON.parse(raw),tokens=[];
async function request(i,path,body,method='POST',headers={}){const res=await fetch(url+path,{method,headers:{apikey:key,...(tokens[i]?{Authorization:'Bearer '+tokens[i]}:{}),'Content-Type':'application/json',...headers},body:body===undefined?undefined:body instanceof Uint8Array?body:JSON.stringify(body),signal:AbortSignal.timeout(20000)});const text=await res.text();let data;try{data=JSON.parse(text);}catch{data=text;}return {status:res.status,data};}
async function rpc(i,name,args={}){const r=await request(i,'/rest/v1/rpc/'+name,args);assert.ok([200,204].includes(r.status),JSON.stringify(r.data));return r.data;}
async function command(i,action,args){return rpc(i,'social_command',{p_action:action,p_args:args,p_request_id:crypto.randomUUID()});}
try{
 assert.equal(cfg.accounts.length,3);assert.ok(cfg.run.startsWith('social-'));
 for(let i=0;i<3;i++){assert.ok(/^qa_social_(alpha|beta|gamma)\.social-\d+@example\.invalid$/.test(cfg.accounts[i].email));const r=await request(i,'/auth/v1/token?grant_type=password',{email:cfg.accounts[i].email,password:cfg.password});assert.equal(r.status,200,'QA login failed');assert.equal(r.data.user.app_metadata.qa_run,cfg.run);assert.equal(r.data.user.id,cfg.accounts[i].id);tokens[i]=r.data.access_token;}
 if(cfg.cleanup){
  for(let i=0;i<3;i++){const removed=await request(i,'/storage/v1/object/avatars',{prefixes:[cfg.accounts[i].id+'/avatar.webp']},'DELETE');assert.equal(removed.status,200,'QA portrait cleanup');const logout=await request(i,'/auth/v1/logout',{});assert.ok([200,204].includes(logout.status));}
  console.log('QA portraits removed and QA Auth sessions signed out.');
 }else{
 const profiles=await request(0,'/rest/v1/profiles?select=*',undefined,'GET');assert.equal(profiles.data.length,1);
 const avatar=cfg.accounts[0].id+'/avatar.webp';const upload=await request(0,'/storage/v1/object/avatars/'+avatar,await readFile('dist/assets/art/race_vael.webp'),'POST',{'Content-Type':'image/webp','x-upsert':'true'});assert.equal(upload.status,200);
 const patched=await request(0,'/rest/v1/profiles?id=eq.'+cfg.accounts[0].id,{avatar_path:avatar},'PATCH');assert.ok([200,204].includes(patched.status));
 assert.equal((await request(1,'/storage/v1/object/sign/avatars/'+avatar,{expiresIn:60})).status,200,'Other active player can render portrait');
 const clan=await rpc(0,'my_clan');assert.equal(clan.name,'QA Social Test');await rpc(1,'manage_clan',{p_action:'join',p_clan_id:clan.id,p_name:null});
 const privateThread=(await command(0,'thread',{scope:'clan',title:'QA — Canal privé',body:'Contrôle privé : seuls les membres de ce clan peuvent lire ce message.'})).thread_id;
 let f=await rpc(1,'social_feed',{p_scope:'clan',p_thread_id:privateThread});assert.equal(f.posts[0].author.username,'QA_Social_Alpha');await command(1,'reply',{thread_id:privateThread,body:'Canal privé reçu par le second membre.'});
 const denied=await request(2,'/rest/v1/rpc/social_feed',{p_scope:'clan',p_thread_id:privateThread});assert.ok(denied.status>=400,'Outsider read denied');
 const planetConversation=(await command(1,'message',{kind:'planet',target_id:cfg.accounts[0].planet,title:'QA — Message à votre planète',body:'Bonjour au propriétaire de QA Alpha Prime. Message de test par adresse planétaire.'})).conversation_id;
 f=await rpc(1,'social_feed',{p_conversation_id:planetConversation});assert.equal(f.conversation.peer,'QA Alpha Prime');assert.ok(!JSON.stringify(f.messages).includes('QA_Social_Alpha'));
 assert.ok((await rpc(0,'social_status')).messages.unread);await command(0,'respond',{conversation_id:planetConversation,body:'Le gouverneur de cette planète accuse réception.'});
 f=await rpc(1,'social_feed',{p_conversation_id:planetConversation});assert.equal(f.messages.at(-1).author.username,'QA Alpha Prime');assert.ok(!JSON.stringify(f.messages).includes('QA_Social_Alpha'));
 const playerConversation=(await command(1,'message',{kind:'player',target_id:cfg.accounts[0].empire,title:'QA — Message direct',body:'Correspondance de joueur à joueur.'})).conversation_id;
 assert.ok((await request(2,'/rest/v1/rpc/social_feed',{p_conversation_id:playerConversation})).status>=400,'Private mail isolated');
 const publicFeed=await rpc(1,'social_feed');const thread=publicFeed.threads.find(t=>t.title==='Premier contact — test du forum');assert.ok(thread);await command(1,'reply',{thread_id:thread.id,body:'Transmission reçue. La réponse publique et les indicateurs sont opérationnels.'});
 const unseen=await rpc(0,'social_feed',{p_thread_id:thread.id});assert.ok(unseen.posts.at(-1).unread);await rpc(0,'social_read',{p_channel:'thread:'+thread.id,p_cursor:unseen.posts.at(-1).id});assert.equal((await rpc(0,'social_feed',{p_thread_id:thread.id})).posts.at(-1).unread,false);
 // Leave a new post unread for the browser pass.
 await command(1,'reply',{thread_id:thread.id,body:'Nouveau signal de test : ce message doit apparaître en gras à la première lecture.'});
 console.log(JSON.stringify({passed:true,checks:['real Auth','shared portrait signing','clan isolation','public reply','planet anonymity','player messages','participant isolation','persisted read cursor'],privateThread,planetConversation,playerConversation}));
 }
}catch(error){console.error('FAIL:',error.message);process.exitCode=1;}
