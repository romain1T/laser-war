import {clanMembersView} from './clans.js';
import {escapeHtml as h} from './domain.js';
const err='<p class="form-error" role="alert" hidden></p>';
const date=value=>new Date(value).toLocaleString('fr-FR',{dateStyle:'medium',timeStyle:'short'});
const text=(name,label,max,rows=5)=>`<label class="field">${label}<textarea name="${name}" maxlength="${max}" rows="${rows}" required></textarea></label>`;
export function authorView(author){return `<div class="social-author"><span class="social-avatar" ${author.avatar?`data-social-avatar="${h(author.avatar)}"`:''}>${h(author.username?.charAt(0)||'?')}</span><span><small>${h(author.grade)}</small><b>${h(author.username)}</b></span></div>`;}
const postView=(post)=>`<article class="social-post ${post.unread?'is-unread':''}"><header>${authorView(post.author)}<time>${date(post.created_at)}</time></header><p class="message-body">${h(post.body)}</p>${post.author.signature?`<footer class="post-signature">${h(post.author.signature)}</footer>`:''}</article>`;
const pager=(items,model)=>`<div class="social-pagination">${items.length===50?`<button class="secondary" data-social-older="${h(items[0].id)}">Messages précédents</button>`:''}${model.before?'<button class="text-button" data-social-latest>Derniers messages →</button>':''}</div>`;
const listPager=(items,model)=>`<div class="social-pagination">${items.length===50?`<button class="secondary" data-social-list-older="${h(items.at(-1).latest)}">Discussions précédentes</button>`:''}${model.before?'<button class="text-button" data-social-latest>Discussions récentes →</button>':''}</div>`;
export function forumView(model,clan,clanData){
 const d=model.data;
 return `<div class="social-tabs"><button class="secondary ${model.scope==='public'?'selected':''}" data-forum-scope="public">Forum public</button>${clan?`<button class="secondary ${model.scope==='clan'?'selected':''}" data-forum-scope="clan">[${h(clan.name)}] · Privé</button>`:''}</div>${model.scope==='clan'?clanMembersView(clanData,true):''}${!d?`<p class="empty">${model.error?h(model.error):'Réception des transmissions…'}</p>`:d.thread?`<div class="social-heading"><button class="text-button" data-forum-back>← Discussions</button><h2>${h(d.thread.title)}</h2></div>${pager(d.posts,model)}<div class="social-posts">${d.posts.map(postView).join('')}</div><form class="document-panel social-compose" data-social-action="reply">${text('body','Répondre',5000)}${err}<button class="primary" type="submit">Publier la réponse →</button></form>`:`<section class="document-panel social-thread-list"><div class="section-heading"><h2>${model.scope==='clan'?'Transmissions du clan':'Canal public'}</h2></div>${d.threads.length?d.threads.map(t=>`<button class="social-thread ${t.unread?'is-unread':''}" data-thread="${h(t.id)}"><span><strong>${h(t.title)}</strong><small>${h(t.author.grade)} ${h(t.author.username)}</small></span><span><b>${t.count} message${t.count>1?'s':''}</b><time>${date(t.updated_at)}</time></span></button>`).join(''):'<p class="empty">Aucune discussion. Ouvrez le premier canal.</p>'}</section>${listPager(d.threads,model)}<form class="document-panel social-compose" data-social-action="thread"><h2>Nouvelle discussion</h2><label class="field">Titre<input name="title" minlength="3" maxlength="120" required></label>${text('body','Message',5000)}${err}<button class="primary" type="submit">Créer la discussion →</button></form>`}`;
}
export function messagesView(model){const d=model.data;
 return `<div class="social-heading"><p>Correspondance privée</p><button class="secondary" data-new-message>Nouveau message</button></div>${!d?`<p class="empty">${model.error?h(model.error):'Réception des transmissions…'}</p>`:model.compose?`<form class="document-panel social-compose" data-social-action="message"><h2>Nouvelle transmission</h2><div class="recipient-search"><label class="field">Adresser à<select name="kind"><option value="player">Un joueur</option><option value="planet">Une planète</option></select></label><label class="field">Rechercher un destinataire<input name="query" type="search" minlength="2" maxlength="40" placeholder="Saisir au moins deux caractères" autocomplete="off"></label><div data-recipient-results role="group" aria-label="Destinataires"></div><input type="hidden" name="target_id" required><p class="recipient-choice" data-recipient-choice></p></div><label class="field">Objet<input name="title" minlength="3" maxlength="120" required></label>${text('body','Message',5000)}${err}<button class="primary" type="submit">Envoyer →</button><button class="text-button" type="button" data-message-back>Annuler</button></form>`:d.conversation?`<div class="social-heading"><button class="text-button" data-message-back>← Correspondance</button><h2>${h(d.conversation.subject)}</h2><p>${h(d.conversation.peer)}</p></div>${pager(d.messages,model)}<div class="social-posts">${d.messages.map(postView).join('')}</div><form class="document-panel social-compose" data-social-action="respond">${text('body','Répondre',5000)}${err}<button class="primary" type="submit">Envoyer la réponse →</button></form>`:`<section class="document-panel social-thread-list">${d.conversations.length?d.conversations.map(v=>`<button class="social-thread ${v.unread?'is-unread':''}" data-conversation="${h(v.id)}"><span><strong>${h(v.subject)}</strong><small>${h(v.peer)}</small></span><span><b>${v.count} message${v.count>1?'s':''}</b><time>${date(v.updated_at)}</time></span></button>`).join(''):'<p class="empty">Aucune transmission privée.</p>'}</section>${listPager(d.conversations,model)}`}`;
}
export function signatureView(signature){return `<form id="signature-form" class="social-compose"><h3>Signature</h3><label class="field">Signature du forum<textarea name="signature" maxlength="280" rows="3">${h(signature||'')}</textarea></label>${err}<button class="secondary" type="submit">Enregistrer la signature</button></form>`;}

export function bindSocial({db,state,render,submit,toast,refreshStatus,loadPlayer}){
 const model=state.social;let searchVersion=0;
 const open=async(changes={})=>{const page=state.page,version=state.version,request=(model.request||0)+1;model.request=request;model.loading=true;Object.assign(model,{before:null,...changes,data:null,error:null});render();try{
  const {data,error}=await db.rpc('social_feed',{p_scope:model.scope,p_thread_id:model.thread,p_conversation_id:model.conversation,p_before:model.before});if(error)throw error;if(request!==model.request||version!==state.version||page!==state.page)return;model.data=data;state.unread=data.status;render();
  const entries=page==='forum'?(model.thread?data.posts:data.threads.map(t=>({id:t.latest}))):data.messages;
  const channel=page==='forum'?(model.thread?'thread:'+model.thread:'forum:'+model.scope):(model.conversation?'conversation:'+model.conversation:null);
  if(channel){const cursor=entries.reduce((a,p)=>BigInt(p.id)>BigInt(a)?p.id:a,'0');const {error:readError}=await db.rpc('social_read',{p_channel:channel,p_cursor:cursor});if(readError)throw readError;}
  await refreshStatus();
 }catch(error){if(request===model.request&&version===state.version&&page===state.page){model.error=error.message;model.data=null;render();toast(error.message);}}finally{if(request===model.request)model.loading=false;}};
 document.querySelectorAll('[data-forum-scope]').forEach(b=>b.onclick=()=>open({scope:b.dataset.forumScope,thread:null}));
 document.querySelectorAll('[data-thread]').forEach(b=>b.onclick=()=>open({thread:b.dataset.thread}));
 document.querySelectorAll('[data-conversation]').forEach(b=>b.onclick=()=>open({conversation:b.dataset.conversation,compose:false}));
 document.querySelector('[data-forum-back]')?.addEventListener('click',()=>open({thread:null}));
 document.querySelector('[data-message-back]')?.addEventListener('click',()=>open({conversation:null,compose:false}));
 document.querySelector('[data-new-message]')?.addEventListener('click',()=>{model.compose=true;model.conversation=null;render();});
 document.querySelector('[data-social-older]')?.addEventListener('click',e=>open({before:e.currentTarget.dataset.socialOlder}));
 document.querySelector('[data-social-list-older]')?.addEventListener('click',e=>open({before:e.currentTarget.dataset.socialListOlder}));
 document.querySelector('[data-social-latest]')?.addEventListener('click',()=>open());
 const send=async(action,args)=>{
  const key='lw-social-command:'+state.user.id;let pending;try{pending=JSON.parse(sessionStorage.getItem(key)||'null');}catch{}
  const payload={p_action:action,p_args:args};if(pending&&JSON.stringify(pending.payload)!==JSON.stringify(payload))throw Error('Une transmission est en attente. Renvoyez le même contenu pour la confirmer.');
  pending||={id:crypto.randomUUID(),payload};sessionStorage.setItem(key,JSON.stringify(pending));
  const {data,error}=await db.rpc('social_command',{...payload,p_request_id:pending.id});if(error){if(error.code)sessionStorage.removeItem(key);throw error;}sessionStorage.removeItem(key);return data;
 };
 const recoveryKey='lw-social-command:'+state.user.id;let recovery;try{recovery=JSON.parse(sessionStorage.getItem(recoveryKey)||'null');}catch{}
 if(recovery&&!document.querySelector('#resume-social')){
  const button=document.createElement('button');button.id='resume-social';button.className='secondary social-retry';button.textContent='Reprendre la transmission interrompue';
  button.onclick=async()=>{button.disabled=true;try{const result=await send(recovery.payload.p_action,recovery.payload.p_args);if(recovery.payload.p_action==='signature'){await loadPlayer();return;}state.page=result.thread_id?'forum':'messages';await open({scope:recovery.payload.p_args.scope||model.scope,thread:result.thread_id||null,conversation:result.conversation_id||null,compose:false});}catch(error){toast(error.message);button.disabled=false;}};
  document.querySelector('#game-content')?.prepend(button);
 }
 document.querySelector('#signature-form')?.addEventListener('submit',e=>{e.preventDefault();submit(e.currentTarget,async f=>{await send('signature',{signature:f.get('signature')});await loadPlayer();toast('Signature enregistrée.');});});
 document.querySelectorAll('[data-social-action]').forEach(form=>form.onsubmit=e=>{e.preventDefault();submit(form,async f=>{
  const action=form.dataset.socialAction,args=Object.fromEntries(f);if(action==='message'&&!args.target_id)throw Error('Choisissez un destinataire dans les résultats.');
  if(action==='thread')args.scope=model.scope;if(action==='reply')args.thread_id=model.thread;if(action==='respond')args.conversation_id=model.conversation;
  delete args.query;const result=await send(action,args);await open({thread:result.thread_id||null,conversation:result.conversation_id||null,compose:false});
 });});
 const form=document.querySelector('[data-social-action="message"]');
 if(form){const search=async()=>{const version=++searchVersion;form.elements.target_id.value='';form.querySelector('[data-recipient-choice]').textContent='';const query=form.elements.query.value.trim(),results=form.querySelector('[data-recipient-results]');results.replaceChildren();if(query.length<2)return;
  await new Promise(resolve=>setTimeout(resolve,250));if(version!==searchVersion)return;
  const {data,error}=await db.rpc('social_targets',{p_kind:form.elements.kind.value,p_query:query});if(version!==searchVersion||!form.isConnected)return;if(error){results.textContent=error.message;return;}
  if(!data.length){results.textContent='Aucun destinataire trouvé.';return;}
  data.forEach(target=>{const b=document.createElement('button');b.type='button';b.className='secondary';b.textContent=target.label;b.onclick=()=>{form.elements.target_id.value=target.id;form.querySelector('[data-recipient-choice]').textContent='À : '+target.label;results.replaceChildren();};results.append(b);});
 };form.elements.query.oninput=search;form.elements.kind.onchange=search;}
 // Only the initial navigation fetches here; later renders retain the captured unread snapshot.
 if(['forum','messages'].includes(state.page)&&!model.data&&!model.loading&&!model.error)open();
}

const avatarCache=new Map();
export async function loadSocialAvatars(db){const nodes=[...document.querySelectorAll('[data-social-avatar]')];const paths=[...new Set(nodes.map(n=>n.dataset.socialAvatar))];await Promise.all(paths.map(async path=>{let cached=avatarCache.get(path);if(!cached||cached.expires<Date.now()){const {data,error}=await db.storage.from('avatars').createSignedUrl(path,300);if(error)return;cached={url:data.signedUrl,expires:Date.now()+240000};avatarCache.set(path,cached);}nodes.filter(n=>n.dataset.socialAvatar===path&&n.isConnected).forEach(n=>{const image=new Image();image.src=cached.url;image.alt='';n.replaceChildren(image);});}));}
