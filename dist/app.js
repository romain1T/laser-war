import { SUPABASE_URL, SUPABASE_KEY } from './config.js';
import { races, resources, number, escapeHtml as h, validateFounding, readEmailLink, planetLabel } from './domain.js';
import { clanPanel, planetOptions } from './clans.js';
import { galaxyView } from './galaxy.js';

// The locally vendored official client is loaded before this module.
const { createClient } = window.supabase;
const db = createClient(SUPABASE_URL, SUPABASE_KEY);
const app = document.querySelector('#app');
const state = { user:null, profile:null, empire:null, planets:[], season:null, page:'planets', auth:'login', recovery:false, active:0, version:0, clan:null, clans:[], signals:[], selectedSignal:null, mapZoom:1 };
const icon = (name, cls='') => `<svg class="icon ${cls}" aria-hidden="true" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.4" stroke-linecap="round" stroke-linejoin="round">${({planet:'<circle cx="12" cy="12" r="7"/><ellipse cx="12" cy="12" rx="12" ry="3" transform="rotate(-30 12 12)"/>',command:'<path d="m12 2 9 17-9-4-9 4Z"/><path d="m8 20 4 2 4-2"/>',map:'<path d="m3 5 6-3 6 3 6-3v17l-6 3-6-3-6 3Z"/><path d="M9 2v17M15 5v17"/>',fleet:'<path d="m12 2 8 19-8-4-8 4Z"/><path d="M12 7v10"/>',research:'<circle cx="12" cy="4" r="2"/><circle cx="5" cy="19" r="2"/><circle cx="19" cy="19" r="2"/><path d="M12 6v6M5 17v-5h14v5"/>',user:'<circle cx="12" cy="8" r="4"/><path d="M4 22v-3a8 8 0 0 1 16 0v3"/>',help:'<circle cx="12" cy="12" r="9"/><path d="M9 9a3 3 0 1 1 5 2c-2 1-2 1-2 3M12 17h.01"/>',arrow:'<path d="M4 12h16m-6-6 6 6-6 6"/>',logout:'<path d="M10 3H4v18h6M9 12h12m-5-5 5 5-5 5"/>',refresh:'<path d="M20 8a8 8 0 1 0 0 8M20 3v5h-5"/>',bell:'<path d="M5 17h14l-2-4V9a5 5 0 0 0-10 0v4ZM10 21h4"/>',trade:'<path d="M3 7h18m-4-4 4 4-4 4M21 17H3m4-4-4 4 4 4"/>',shield:'<path d="m12 2 8 4v6c0 5-8 10-8 10S4 17 4 12V6Z"/>',sun:'<circle cx="12" cy="12" r="4"/><path d="M12 1v3m0 16v3M1 12h3m16 0h3M4 4l2 2m12 12 2 2M4 20l2-2M18 6l2-2"/>',chevron:'<path d="m9 5 7 7-7 7"/>',clock:'<circle cx="12" cy="12" r="9"/><path d="M12 6v6l4 2"/>'})[name] || ''}</svg>`;
const brand = () => `<a class="brand" href="#" aria-label="Laser War, accueil"><img src="/assets/emblem.svg" alt=""><span>LASER<span class="brand-light">WAR</span><small>CHRONIQUES INTERSTELLAIRES</small></span></a>`;
function toast(text) { const el=document.querySelector('#toast'); el.textContent=text; el.classList.add('visible'); clearTimeout(toast.timer); toast.timer=setTimeout(()=>el.classList.remove('visible'),5000); }
function errorText(error) {
  const m=error?.message || String(error);
  if (/Invalid login credentials/i.test(m)) return 'Adresse e-mail ou mot de passe incorrect.';
  if (/Email not confirmed/i.test(m)) return 'Confirme ton adresse e-mail avant de te connecter.';
  if (/Email link is invalid or has expired|Token has expired|otp_expired/i.test(m)) return 'Ce lien a expiré ou a déjà été utilisé. Si vous l’avez déjà ouvert, votre adresse peut être confirmée : revenez à la connexion. Sinon, demandez un nouvel e-mail.';
  if (/rate limit|too many requests/i.test(m)) return 'Trop de tentatives. Patiente quelques minutes avant de réessayer.';
  if (/email address.*invalid|email_address_invalid/i.test(m)) return 'Cette adresse e-mail ne peut pas être utilisée.';
  if (/email.*not authorized|only send.*email|email_address_not_authorized/i.test(m)) return 'L’envoi d’e-mails est encore limité par Supabase. Un service e-mail doit être configuré pour ouvrir les inscriptions à tous.';
  if (/Failed to fetch|NetworkError/i.test(m)) return 'Liaison interrompue. Vérifie ta connexion puis réessaie.';
  return m;
}
function showError(form,error) { const el=form.querySelector('.form-error'); el.textContent=errorText(error); el.hidden=false; }
async function submit(form,action) {
  const button=form.querySelector('[type=submit]');
  if(button.disabled) return;
  button.disabled=true; form.setAttribute('aria-busy','true'); form.querySelector('.form-error').hidden=true;
  try { await action(new FormData(form)); } catch(error) { showError(form,error); }
  finally { button.disabled=false; form.removeAttribute('aria-busy'); }
}
const errorBox = '<p class="form-error" role="alert" hidden></p>';
const input = (name,label,type='text',extra='') => `<label class="field">${label}<input name="${name}" type="${type}" required ${extra}></label>`;
function authView() {
  const mode=state.recovery?'new-password':state.auth;
  const signup=mode==='signup', reset=mode==='reset', verify=mode==='verify', newPass=mode==='new-password';
  const title=signup?'Votre odyssée commence ici.':reset?'Retrouvez votre commandement.':verify?'Confirmez votre identité.':newPass?'Sécurisez votre accès.':'Les étoiles vous attendent.';
  app.innerHTML=`<main class="auth-layout"><header class="auth-top">${brand()}<span class="alpha-label"><i></i> ALPHA · SESSION 01</span></header><section class="auth-story"><div class="eyebrow">STRATÉGIE SPATIALE · UNIVERS PERSISTANT</div><h1>Un monde pour origine.<br>Les étoiles<br><em>pour horizon.</em></h1><p>Développez vos planètes. Tracez vos alliances.<br>Écrivez l’histoire de votre empire.</p><div class="story-coordinates"><span class="coordinate-cross">+</span><span>SECTEUR ORIGINEL<br><b>UNE NOUVELLE ÈRE COMMENCE</b></span></div></section><section class="auth-panel" aria-labelledby="auth-title"><div class="panel-index">TRANSMISSION SÉCURISÉE <span>01 / ACCÈS</span></div><div class="auth-heading"><span class="tiny-line"></span><h2 id="auth-title">${title}</h2><p>${signup?'Enregistrez votre identité de commandant.':reset?'Recevez un lien de récupération par e-mail.':verify?'Utilisez le lien reçu dans votre boîte e-mail.':newPass?'Choisissez un nouveau mot de passe.':'Reprenez les commandes de votre empire.'}</p></div>${!reset&&!verify&&!newPass?`<div class="auth-tabs"><button data-auth="login" class="${!signup?'selected':''}">Connexion</button><button data-auth="signup" class="${signup?'selected':''}">Créer un compte</button></div>`:''}<form id="auth-form">${signup?input('username','Nom de commandant','text','minlength="3" maxlength="24" pattern="[a-zA-Z0-9_-]{3,24}" autocomplete="username" placeholder="Votre indicatif"'):''}${!newPass&&!verify?input('email','Adresse e-mail','email','autocomplete="email" placeholder="commandant@exemple.fr"'):''}${verify?`<label class="field">Lien de confirmation ou de récupération<textarea name="link" required rows="3" placeholder="Collez ici le lien complet reçu par e-mail" autocomplete="off" spellcheck="false"></textarea></label><p class="form-note">Copiez le lien du bouton dans l’e-mail. Cela permet aussi de confirmer votre compte si la redirection de l’e-mail n’est pas encore configurée.</p>`:''}${!reset&&!verify?`<label class="field">Mot de passe<div class="password-field"><input name="password" type="password" required ${signup||newPass?'minlength="10"':''} autocomplete="${signup||newPass?'new-password':'current-password'}" placeholder="${signup||newPass?'10 caractères minimum':'Votre mot de passe'}"><button class="password-toggle" type="button" aria-label="Afficher le mot de passe">Voir</button></div></label>`:''}${!signup&&!reset&&!verify&&!newPass?'<button class="text-button forgot" type="button" data-auth="reset">Mot de passe oublié ?</button>':''}${errorBox}<button class="primary" type="submit">${signup?'Rejoindre l’univers':reset?'Envoyer le lien':verify?'Vérifier mon lien':newPass?'Enregistrer le mot de passe':'Accéder au commandement'}${icon('arrow')}</button></form><div class="auth-bottom">${reset||verify?'<button class="text-button" data-auth="login">Retour à la connexion</button>':newPass?'<span>Votre mot de passe n’est jamais stocké dans le jeu.</span>':'<span>Un empire. Douze mondes. Votre histoire.</span>'}${!verify&&!newPass?'<button class="text-button" data-auth="verify">J’ai reçu un lien par e-mail</button>':''}</div></section><footer class="auth-footer"><span>LASER WAR <b>/</b> ALPHA 0.1</span><span>Un univers qui continue de vivre en votre absence.</span></footer></main>`;
  document.querySelectorAll('[data-auth]').forEach(b=>b.onclick=()=>{state.auth=b.dataset.auth;state.recovery=false;authView();});
  document.querySelector('.password-toggle')?.addEventListener('click',e=>{const i=e.currentTarget.previousElementSibling; const reveal=i.type==='password'; i.type=reveal?'text':'password';e.currentTarget.textContent=reveal?'Masquer':'Voir'; e.currentTarget.setAttribute('aria-label',reveal?'Masquer le mot de passe':'Afficher le mot de passe');});
  document.querySelector('#auth-form').onsubmit=e=>{e.preventDefault();submit(e.currentTarget,async f=>{
    const email=String(f.get('email')||'').trim();
    if(signup) {
      const {data,error}=await db.auth.signUp({email,password:f.get('password'),options:{data:{username:f.get('username')},emailRedirectTo:location.origin}});
      if(error) throw error;
      if(data.session) await loadPlayer(); else { state.auth='verify';authView();toast('Compte enregistré. Consultez votre e-mail pour confirmer votre adresse.'); }
    } else if(reset) {
      const {error}=await db.auth.resetPasswordForEmail(email,{redirectTo:location.origin}); if(error) throw error;
      state.auth='verify';authView();toast('Si un compte correspond à cette adresse, un lien de récupération vous sera envoyé.');
    } else if(verify) {
      const params=readEmailLink(f.get('link')); const {error}=await db.auth.verifyOtp(params); if(error) throw error;
      if(params.type==='recovery'){state.recovery=true;authView();}else{await loadPlayer();}
    } else if(newPass) {
      const {error}=await db.auth.updateUser({password:f.get('password')}); if(error) throw error;
      state.recovery=false;toast('Mot de passe enregistré.');await loadPlayer();
    } else {
      const {error}=await db.auth.signInWithPassword({email,password:f.get('password')});if(error) throw error;await loadPlayer();
    }
  });};
}
async function loadPlayer() {
  const version=++state.version;
  const {data:{user},error}=await db.auth.getUser();
  if(version!==state.version)return;
  if(error||!user){state.user=null;authView();return;}
  state.user=user;
  if(state.recovery){authView();return;}
  const results=await Promise.all([db.from('profiles').select('*').eq('id',user.id).maybeSingle(),db.from('empires').select('id,season_id,player_id,treasury,grade,created_at').eq('player_id',user.id).order('created_at',{ascending:false}),db.from('seasons').select('*').eq('status','alpha').maybeSingle()]);
  if(version!==state.version)return;
  const failed=results.find(r=>r.error);if(failed){fatal(failed.error);return;}
  state.profile=results[0].data;state.season=results[2].data;
  state.empire=results[1].data.find(e=>e.season_id===state.season?.id) || null;
  if(!state.empire){onboarding();return;}
  const gameData=await Promise.all([
    db.from('planets').select('*').eq('owner_empire_id',state.empire.id).order('created_at'),
    db.rpc('my_clan'),db.from('clans').select('id,name').eq('season_id',state.empire.season_id).order('name').limit(500),db.rpc('galaxy_signals')
  ]);
  if(version!==state.version)return;
  const gameError=gameData.find(r=>r.error);if(gameError){fatal(gameError.error);return;}
  state.planets=gameData[0].data;state.clan=gameData[1].data;state.clans=gameData[2].data;state.signals=gameData[3].data;
  if(!state.signals.some(p=>p.id===state.selectedSignal))state.selectedSignal=state.planets[0]?.id||state.signals[0]?.id;
  state.active=Math.min(state.active,Math.max(0,state.planets.length-1));renderGame();
}
function fatal(error){app.innerHTML=`<div class="boot"><h1>Liaison interrompue</h1><p>${h(errorText(error))}</p><button class="primary" id="retry">Réessayer</button><button class="text-button" id="signout">Se déconnecter</button></div>`;document.querySelector('#retry').onclick=loadPlayer;document.querySelector('#signout').onclick=signout;}
function onboarding(){
  app.innerHTML=`<main class="auth-layout onboarding"><header class="auth-top">${brand()}<button class="text-button" id="signout">Se déconnecter ${icon('logout')}</button></header><section class="auth-story"><div class="eyebrow">PREMIER CONTACT</div><h1>Votre histoire<br>commence par<br><em>un monde.</em></h1><p>Votre planète d’origine vous attend.<br>Donnez-lui un nom. Le reste de l’histoire vous appartient.</p></section><section class="auth-panel"><div class="panel-index">PREMIÈRE COLONIE <span>02 / ORIGINE</span></div><div class="auth-heading"><h2>Nommez votre première planète.</h2><p>Sa race et sa ressource seront attribuées automatiquement.</p></div><form id="found-form">${input('username','Nom de commandant','text',`minlength="3" maxlength="24" pattern="[a-zA-Z0-9_-]{3,24}" value="${h(state.profile?.username||state.user.user_metadata?.username||'')}" autocomplete="username"`)}${input('planet','Nom de la planète d’origine','text','minlength="3" maxlength="40" placeholder="Ex. Nova Prime"')}<p class="form-note">Ce nom consomme le choix de renommage de votre planète d’origine.</p>${errorBox}<button class="primary" type="submit">Établir ma planète ${icon('arrow')}</button></form><p class="alpha-note">Session Alpha · Équilibrage de départ provisoire.</p></section></main>`;
  document.querySelector('#signout').onclick=signout;
  document.querySelector('#found-form').onsubmit=e=>{e.preventDefault();submit(e.currentTarget,async f=>{
    const values={username:String(f.get('username')).trim(),planet:String(f.get('planet')).trim()};
    const invalid=validateFounding(values);if(invalid)throw Error(invalid);
    const {error}=await db.rpc('start_player',{p_username:values.username,p_planet_name:values.planet});if(error)throw error;
    await loadPlayer();toast('Votre premier monde est établi. Bienvenue, commandant.');
  });};
}
async function signout(){const {error}=await db.auth.signOut();if(error){toast(errorText(error));return;}state.version++;Object.assign(state,{user:null,profile:null,empire:null,planets:[],auth:'login',recovery:false,page:'planets',clan:null,clans:[],signals:[],selectedSignal:null});authView();}
const navigation=[['command','command','Commandement',false],['planets','planet','Planètes',false],['trade','trade','Commerce',true],['map','map','Carte galactique',false],['fleets','fleet','Armées & flottes',true],['research','research','Technologies',true]];
function renderGame(){
  const p=state.planets[state.active];
  app.innerHTML=`<div class="game-layout"><aside class="sidebar">${brand()}<div class="sidebar-sector"><span class="eyebrow">COMMANDANT</span><strong>${h(state.profile.username)}</strong><small>${h(state.season?.name||'Session terminée')}</small></div><nav aria-label="Navigation principale">${navigation.map(([key,ico,label,disabled])=>`<button data-page="${key}" ${disabled?'disabled title="Disponible dans une prochaine version"':''} class="nav-item ${state.page===key?'active':''}">${icon(ico)}<span>${label}</span>${disabled?'<span class="soon">À VENIR</span>':icon('chevron')}</button>`).join('')}</nav><div class="sidebar-bottom"><button class="nav-item ${state.page==='account'?'active':''}" data-page="account">${icon('user')}<span>Compte & clan</span></button><button class="nav-item ${state.page==='help'?'active':''}" data-page="help">${icon('help')}<span>Archives & aide</span></button><div class="server-status"><i></i> LIAISON ÉTABLIE <span>ALPHA 0.1</span></div></div></aside><div class="main-shell"><header class="topbar"><button class="commander" data-page="account"><span class="commander-avatar">${h(state.profile.username.charAt(0).toUpperCase())}</span><span><small>${h(state.empire.grade)}</small><b>${h(state.profile.username)}</b></span></button><button class="treasury" data-page="revenues"><span>TRÉSORERIE</span><strong>${number(state.empire.treasury)} <em>Þ</em></strong></button><div class="top-tools"><button class="icon-button" data-page="alerts" aria-label="Notifications et alertes">${icon('bell')}</button><button class="icon-button" disabled aria-label="Flottes en transit, à venir" title="Flottes en transit · à venir">${icon('fleet')}</button><button class="top-link" disabled title="Civilisation · à venir">Civilisation</button><button class="top-link" data-page="help">Aide</button><span class="forum" title="Le forum sera développé ultérieurement">Forum <small>À VENIR</small></span><button class="icon-button" id="signout" aria-label="Se déconnecter">${icon('logout')}</button></div></header><main id="game-content">${state.page==='planets'?planetView(p):state.page==='command'?commandView():state.page==='account'?accountView():state.page==='map'?mapView():state.page==='help'?helpView():state.page==='revenues'?revenueView():alertsView()}</main><footer class="game-footer"><span><i></i> DONNÉES SAUVEGARDÉES SUR LE SERVEUR</span><span>LASER WAR · UNIVERS ALPHA</span></footer></div></div>`;
  document.querySelectorAll('[data-page]').forEach(b=>b.onclick=()=>{state.page=b.dataset.page;renderGame();});
  document.querySelector('#signout').onclick=signout;
  document.querySelector('#refresh')?.addEventListener('click',async e=>{e.currentTarget.disabled=true;await loadPlayer();toast('Données actualisées.');});
  document.querySelectorAll('[data-planet]').forEach(b=>b.onclick=()=>{state.active=Number(b.dataset.planet);renderGame();});
  document.querySelector('#avatar-form')?.addEventListener('submit',e=>{e.preventDefault();submit(e.currentTarget,uploadAvatar);});
  if(state.page==='account'){loadAvatar();bindClans();}
  document.querySelector('#planet-options-form')?.addEventListener('submit',savePlanetOptions);
  if(state.page==='map')bindMap();
}
function pageHeader(kicker,title,subtitle=''){return `<div class="page-heading"><div><div class="eyebrow">${kicker}</div><h1>${title}</h1>${subtitle?`<p>${subtitle}</p>`:''}</div><button id="refresh" class="refresh" title="Actualiser depuis le serveur">${icon('refresh')}<span>Actualiser</span></button></div>`;}
function planetView(p){
  if(!p)return pageHeader('VOS MONDES','Aucune planète')+'<p class="empty">Aucune planète sous votre contrôle.</p>';
  const r=races[p.race],resource=resources[p.resource];
  return `${pageHeader('TERRITOIRES IMPÉRIAUX','Vos planètes','Chaque monde est le commencement d’une nouvelle histoire.')}<div class="planet-selector"><span>MONDES CONTRÔLÉS <b>${state.planets.length}<small> / 12</small></b></span><div class="planet-tabs">${state.planets.map((world,i)=>`<button data-planet="${i}" class="planet-tab ${i===state.active?'selected':''}"><span class="mini-planet"></span><span>${h(planetLabel(world,state.clan))}<small>${i===0?'MONDE D’ORIGINE':'MONDE IMPÉRIAL'}</small></span>${icon('chevron')}</button>`).join('')}</div></div><section class="planet-hero" aria-labelledby="planet-name"><div class="orbital-grid" aria-hidden="true"></div><div class="planet-hero-top"><span class="pill"><i></i> SOUS VOTRE CONTRÔLE</span><span class="coords">X ${Math.round(p.x)} · Y ${Math.round(p.y)}</span></div><div class="planet-hero-copy"><div class="eyebrow">${state.active===0?'VOTRE MONDE D’ORIGINE':'DOMAINE IMPÉRIAL'}</div><h2 id="planet-name">${h(p.name)}${p.clan_tag_visible&&state.clan?` <span class="clan-tag">[${h(state.clan.name)}]</span>`:''}</h2><p>Un point de lumière.<br>Le berceau de votre empire.</p><div class="planet-traits"><span title="${h(r.effect)}"><b>${r.icon}</b><span>${r.name}<small>${r.description}</small></span></span><span title="${h(resource.effect)}"><b>${resource.icon}</b><span>${resource.name}<small>${resource.description}</small></span></span></div></div><div class="hero-bottom"><span>${icon('shield')} ${p.governance==='conseil'?'Gouvernée par un Conseil':'Gouvernée par une Tyrannie'}</span><span>ARCHIVES PLANÉTAIRES <b>01</b></span></div></section><div class="planet-sections"><section class="stat-section"><div class="section-heading">${icon('user')}<h3>Population & civilisation</h3><span>01</span></div><div class="big-stat">${number(p.population)}<small>HABITANTS</small></div><div class="stat-row"><span>Niveau de civilisation</span><strong>${p.civilization}</strong></div><div class="level-line" aria-hidden="true"><span></span></div><p class="section-note">Assimilation et croissance disponibles dans une prochaine version.</p></section><section class="stat-section"><div class="section-heading">${icon('trade')}<h3>Économie & commerce</h3><span>02</span></div><div class="big-stat">${p.trade_capacity}<small>CAPACITÉS CONSTRUITES / 200</small></div><div class="stat-row"><span>Ressource principale</span><strong>${resource.icon} ${resource.name}</strong></div><p class="section-note">${resource.effect}. Production et liaisons à venir.</p></section><section class="stat-section"><div class="section-heading">${icon('shield')}<h3>Garnison & gouvernance</h3><span>03</span></div><div class="big-stat">${number(p.soldiers)}<small>SOLDATS EN GARNISON</small></div><div class="stat-row"><span>Vaisseaux stationnés</span><strong>${p.scouts+p.bombers+p.fighters}</strong></div><p class="section-note">${p.governance==='conseil'?'Conseil : croissance +20 % · production de soldats −20 %.':'Tyrannie : croissance −20 % · production de soldats +20 %.'} Simulation à venir.</p></section><section class="stat-section"><div class="section-heading">${icon('sun')}<h3>Énergie & identité</h3><span>04</span></div><div class="big-stat">${p.energy}<span class="stat-max"> / ${p.energy_max}</span><small>RÉSERVE D’ÉNERGIE LOCALE</small></div><div class="stat-row"><span>Renommage initial</span><strong>${p.rename_available?'Disponible':'Utilisé'}</strong></div><p class="section-note">L’énergie nécessite une recherche. Désignation de la capitale à venir.</p></section></div>${planetOptions(p,state.clan)}<div class="alpha-banner"><span>ALPHA</span><p>Votre empire et votre planète sont sauvegardés. Économie, recherche et combats seront activés progressivement.</p></div>`;
}
function commandView(){return `${pageHeader('CENTRE DE COMMANDEMENT','Bienvenue, commandant.')}<section class="command-hero"><div class="eyebrow">${h(state.profile.username)}</div><h2>L’avenir se construit<br><em>parmi les étoiles.</em></h2><p>Votre premier monde est établi. Prenez connaissance de ses ressources avant de tracer votre prochaine route.</p><button class="primary" data-page="planets">Explorer ma planète ${icon('arrow')}</button></section><div class="command-summary"><span><b>${state.planets.length}</b> MONDE SOUS VOTRE CONTRÔLE</span><span><b>${number(state.empire.treasury)} Þ</b> TRÉSORERIE IMPÉRIALE</span></div>`;}
function accountView(){return `${pageHeader('IDENTITÉ IMPÉRIALE','Votre compte')}<div class="document-panel"><div class="account-intro"><div class="large-avatar" id="avatar-preview">${h(state.profile.username.charAt(0).toUpperCase())}</div><div><div class="eyebrow">${h(state.empire.grade)}</div><h2>${h(state.profile.username)}</h2><p>${h(state.user.email)}</p></div></div><form id="avatar-form"><h3>Portrait du commandant</h3><label class="field">Choisir une image<input name="avatar" type="file" accept="image/png,image/jpeg,image/webp" required></label><p class="form-note">PNG, JPEG ou WebP · 2 Mo maximum. Le portrait est recadré en carré et stocké dans votre espace privé.</p>${errorBox}<button class="secondary" type="submit">Enregistrer le portrait</button></form><hr>${clanPanel(state.clan,state.clans)}<h3>Grade</h3><p>Matelot est le grade de départ provisoire. La progression des grades n’est pas encore implémentée.</p><h3>Sécurité</h3><p>Pour changer votre mot de passe, déconnectez-vous puis utilisez « Mot de passe oublié ».</p></div>`;}
async function loadAvatar(){if(!state.profile.avatar_path)return; const {data,error}=await db.storage.from('avatars').createSignedUrl(state.profile.avatar_path,300);const el=document.querySelector('#avatar-preview');if(!error&&el){const img=new Image();img.src=data.signedUrl;img.alt='Portrait du commandant';el.replaceChildren(img);}}
async function uploadAvatar(f){
  const file=f.get('avatar');if(!(file instanceof File)||!['image/png','image/jpeg','image/webp'].includes(file.type)||file.size>2097152)throw Error('Choisissez une image PNG, JPEG ou WebP de 2 Mo maximum.');
  const bitmap=await createImageBitmap(file);const size=Math.min(bitmap.width,bitmap.height);if(!size)throw Error('Image illisible.');
  const canvas=document.createElement('canvas');canvas.width=canvas.height=256;canvas.getContext('2d').drawImage(bitmap,(bitmap.width-size)/2,(bitmap.height-size)/2,size,size,0,0,256,256);bitmap.close();
  const blob=await new Promise(resolve=>canvas.toBlob(resolve,'image/webp',0.88));if(!blob)throw Error('Impossible de convertir cette image.');
  const path=state.user.id+'/avatar.webp';const {error}=await db.storage.from('avatars').upload(path,blob,{upsert:true,contentType:'image/webp'});if(error)throw error;
  const {data,error:updateError}=await db.from('profiles').update({avatar_path:path}).eq('id',state.user.id).select('avatar_path').single();if(updateError)throw updateError;
  state.profile.avatar_path=data.avatar_path;await loadAvatar();toast('Portrait enregistré.');
}
function helpView(){return `${pageHeader('ARCHIVES IMPÉRIALES','Guide de l’alpha')}<article class="document-panel"><div class="eyebrow">VERSION 0.1 · CE QUI EST JOUABLE</div><h2>Le premier chapitre.</h2><p>Inscription, confirmation de l’e-mail, connexion, récupération du mot de passe, création de votre première planète, portrait du commandant, clans et tags planétaires sur la carte.</p><h3>Règles fixées</h3><p>Une session dure un an. Un empire vise au maximum douze planètes. La race et la ressource appartiennent à chaque planète. Le nom de la planète d’origine est choisi une seule fois à la fondation.</p><h3>Valeurs provisoires de l’alpha</h3><p>100 000 Þ de trésorerie, 1 000 000 d’habitants, civilisation 1, 100 soldats, aucun vaisseau, aucune capacité commerciale et 0/100 énergie. Aucun revenu, recrutement, croissance ou coût d’entretien n’est encore calculé.</p><p>L’univers commence avec 50 mondes. Chaque fondation ajoute 5 mondes, dont celui attribué au joueur. La carte expose les positions des signaux. Un monde extérieur sans tag conserve une désignation anonyme ; les propriétaires, races, ressources et forces ne sont jamais retournés à votre navigateur.</p><h3>Clans et commerce</h3><p>Vous pouvez créer ou rejoindre librement un clan. Chaque planète peut afficher son nom suivi de [Nom du clan], ou conserver son affiliation masquée. Quitter un clan masque tous vos tags ; un nouveau clan ne les réactive pas automatiquement.</p><p>Le commerce sera possible avec toute planète. Le commerce automatique est activé par défaut pour chaque planète ; désactivez-le dans ses options pour examiner les futures demandes avant acceptation. Les liaisons et revenus ne sont pas encore actifs.</p><h3>Races proposées</h3>${Object.values(races).map(r=>`<p><b>${r.icon} ${r.name}</b> — ${r.effect}.</p>`).join('')}<h3>Ressources proposées</h3>${Object.values(resources).map(r=>`<p><b>${r.icon} ${r.name}</b> — ${r.effect}.</p>`).join('')}<p>Les bonus décrivent les règles prévues. Leurs systèmes de production et de combat ne sont pas encore actifs.</p><h3>À venir</h3><p>Liaisons commerciales, revenus quotidiens versés en trois fois, assimilation de civilisation, capitale, recherches, reconnaissance, flottes et combats horaires. Le forum est indisponible.</p><h3>Illustration</h3><p>Illustration orbitale générée pour cette première version ; elle est partagée entre les mondes en attendant les illustrations propres à chaque combinaison race et ressource.</p></article>`;}
function revenueView(){return `${pageHeader('FINANCES IMPÉRIALES','Votre trésorerie')}<section class="document-panel"><div class="eyebrow">DISPONIBLE</div><div class="balance">${number(state.empire.treasury)} <em>Þ</em></div><h3>Économie en préparation</h3><p>Cette somme est sauvegardée sur le serveur. Aucun revenu ni entretien n’est encore calculé ; aucun solde quotidien simulé n’est affiché.</p><button class="secondary" data-page="planets">Revenir aux planètes ${icon('arrow')}</button></section>`;}
function mapView(){return pageHeader('SECTEURS & SIGNATURES','Carte galactique','Affichez votre bannière, ou laissez vos mondes dans l’ombre.')+galaxyView(state.signals,state.selectedSignal,state.mapZoom);}
function bindClans(){
  document.querySelectorAll('[data-clan-action]').forEach(form=>{form.onsubmit=e=>{e.preventDefault();if(!form.querySelector('[type=submit]'))return;submit(form,async f=>{
    const action=form.dataset.clanAction;
    const {error}=await db.rpc('manage_clan',{p_action:action,p_clan_id:action==='leave'?form.dataset.clanId:action==='join'?f.get('clan_id'):null,p_name:action==='create'?String(f.get('clan_name')).trim():null});
    if(error)throw error;await loadPlayer();toast(action==='create'?'Clan créé.':action==='join'?'Vous avez rejoint le clan.':'Vous avez quitté le clan. Vos tags sont masqués.');
  });};});
}
function savePlanetOptions(e){e.preventDefault();const form=e.currentTarget;const planet=state.planets[state.active];submit(form,async f=>{
  const {error}=await db.rpc('set_planet_options',{p_planet_id:planet.id,p_clan_tag_visible:f.get('clan_tag')==='on',p_auto_trade:f.get('auto_trade')==='on'});if(error)throw error;
  await loadPlayer();toast('Options de la planète enregistrées.');
});}
function bindMap(){
  document.querySelectorAll('[data-signal]').forEach(el=>el.onclick=()=>{state.selectedSignal=el.dataset.signal;renderGame();});
  document.querySelector('#signal-select').onchange=e=>{state.selectedSignal=e.target.value;renderGame();};
  document.querySelectorAll('[data-zoom]').forEach(b=>b.onclick=()=>{state.mapZoom=Math.min(3,Math.max(1,state.mapZoom+Number(b.dataset.zoom)*.5));renderGame();});
  document.querySelector('[data-open-planet]')?.addEventListener('click',e=>{const index=state.planets.findIndex(p=>p.id===e.currentTarget.dataset.openPlanet);if(index>=0){state.active=index;state.page='planets';renderGame();}});
}
function alertsView(){return `${pageHeader('TRANSMISSIONS','Notifications & alertes')}<section class="document-panel"><h2>Bienvenue dans la session Alpha.</h2><p>Votre empire a été fondé le ${new Intl.DateTimeFormat('fr-FR',{dateStyle:'long',timeStyle:'short'}).format(new Date(state.empire.created_at))}.</p><p>Les rapports de bataille et alertes de flotte seront reliés à cet écran lors de leur développement.</p></section>`;}
db.auth.onAuthStateChange((event,session)=>{
  if(event==='PASSWORD_RECOVERY'){state.recovery=true;state.user=session?.user;setTimeout(authView,0);}
  else if(event==='SIGNED_OUT'){state.version++;state.user=null;state.profile=null;state.empire=null;state.planets=[];setTimeout(authView,0);}
});
try {
  const hash=new URLSearchParams(location.hash.slice(1));
  if(hash.has('error_description')){toast(hash.get('error_description'));history.replaceState(null,'',location.pathname);}
  const {data:{session}}=await db.auth.getSession();
  if(session)await loadPlayer();else authView();
} catch(error){fatal(error);}
