import {militaryView,missionView,bindMissionDestinations,foreignPresenceView,battleReportsView,militaryHelp,timeLeft} from './military.js';
import {badge,planetArt,civilizationBadge} from './art.js';
import { SUPABASE_URL, SUPABASE_KEY } from './config.js';
import { races, resources, number, escapeHtml as h, validateFounding, readEmailLink, planetLabel } from './domain.js';
import { clanPanel, planetOptions } from './clans.js';
import { galaxyView } from './galaxy.js';
import { revenuesView, tradeView, updateTradeEstimates, bindTradeDestinations } from './economy.js';

// The locally vendored official client is loaded before this module.
const { createClient } = window.supabase;
const db = createClient(SUPABASE_URL, SUPABASE_KEY);
const app = document.querySelector('#app');
const state = { user:null, profile:null, empire:null, planets:[], season:null, page:'planets', auth:'login', recovery:false, active:0, version:0, clan:null, clans:[], signals:[], selectedSignal:null, mapZoom:1, economy:null, tradeData:null, tradePlanetId:null, military:null, militaryPlanetId:null };
const icon = (name, cls='') => `<svg class="icon ${cls}" aria-hidden="true" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.4" stroke-linecap="round" stroke-linejoin="round">${({planet:'<circle cx="12" cy="12" r="7"/><ellipse cx="12" cy="12" rx="12" ry="3" transform="rotate(-30 12 12)"/>',command:'<path d="m12 2 9 17-9-4-9 4Z"/><path d="m8 20 4 2 4-2"/>',map:'<path d="m3 5 6-3 6 3 6-3v17l-6 3-6-3-6 3Z"/><path d="M9 2v17M15 5v17"/>',fleet:'<path d="m12 2 8 19-8-4-8 4Z"/><path d="M12 7v10"/>',research:'<circle cx="12" cy="4" r="2"/><circle cx="5" cy="19" r="2"/><circle cx="19" cy="19" r="2"/><path d="M12 6v6M5 17v-5h14v5"/>',user:'<circle cx="12" cy="8" r="4"/><path d="M4 22v-3a8 8 0 0 1 16 0v3"/>',help:'<circle cx="12" cy="12" r="9"/><path d="M9 9a3 3 0 1 1 5 2c-2 1-2 1-2 3M12 17h.01"/>',arrow:'<path d="M4 12h16m-6-6 6 6-6 6"/>',logout:'<path d="M10 3H4v18h6M9 12h12m-5-5 5 5-5 5"/>',refresh:'<path d="M20 8a8 8 0 1 0 0 8M20 3v5h-5"/>',bell:'<path d="M5 17h14l-2-4V9a5 5 0 0 0-10 0v4ZM10 21h4"/>',trade:'<path d="M3 7h18m-4-4 4 4-4 4M21 17H3m4-4-4 4 4 4"/>',shield:'<path d="m12 2 8 4v6c0 5-8 10-8 10S4 17 4 12V6Z"/>',sun:'<circle cx="12" cy="12" r="4"/><path d="M12 1v3m0 16v3M1 12h3m16 0h3M4 4l2 2m12 12 2 2M4 20l2-2M18 6l2-2"/>',chevron:'<path d="m9 5 7 7-7 7"/>',clock:'<circle cx="12" cy="12" r="9"/><path d="M12 6v6l4 2"/>'})[name] || ''}</svg>`;
const brand = () => '<a class="brand galaxy-brand" href="#" aria-label="Galaxy Simulator, accueil"><img src="/assets/art/logo.webp" alt="Galaxy Simulator" width="240" height="120"></a>';
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
async function submit(form,action,button=form.querySelector('[type=submit]')) {
  if(button.disabled || form.getAttribute('aria-busy')==='true') return;
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
  app.innerHTML=`<main class="auth-layout"><header class="auth-top">${brand()}<span class="alpha-label"><i></i> ALPHA · SESSION 01</span></header><section class="auth-story"><div class="eyebrow">STRATÉGIE SPATIALE · UNIVERS PERSISTANT</div><h1>Un monde pour origine.<br>Les étoiles<br><em>pour horizon.</em></h1><p>Développez vos planètes. Tracez vos alliances.<br>Écrivez l’histoire de votre empire.</p><div class="story-coordinates"><span class="coordinate-cross">+</span><span>SECTEUR ORIGINEL<br><b>UNE NOUVELLE ÈRE COMMENCE</b></span></div></section><section class="auth-panel" aria-labelledby="auth-title"><div class="panel-index">TRANSMISSION SÉCURISÉE <span>01 / ACCÈS</span></div><div class="auth-heading"><span class="tiny-line"></span><h2 id="auth-title">${title}</h2><p>${signup?'Enregistrez votre identité de commandant.':reset?'Recevez un lien de récupération par e-mail.':verify?'Utilisez le lien reçu dans votre boîte e-mail.':newPass?'Choisissez un nouveau mot de passe.':'Reprenez les commandes de votre empire.'}</p></div>${!reset&&!verify&&!newPass?`<div class="auth-tabs"><button data-auth="login" class="${!signup?'selected':''}">Connexion</button><button data-auth="signup" class="${signup?'selected':''}">Créer un compte</button></div>`:''}<form id="auth-form">${signup?input('username','Nom de commandant','text','minlength="3" maxlength="24" pattern="[a-zA-Z0-9_-]{3,24}" autocomplete="username" placeholder="Votre indicatif"'):''}${!newPass&&!verify?input('email','Adresse e-mail','email','autocomplete="email" placeholder="commandant@exemple.fr"'):''}${verify?`<label class="field">Lien de confirmation ou de récupération<textarea name="link" required rows="3" placeholder="Collez ici le lien complet reçu par e-mail" autocomplete="off" spellcheck="false"></textarea></label><p class="form-note">Copiez le lien du bouton dans l’e-mail. Cela permet aussi de confirmer votre compte si la redirection de l’e-mail n’est pas encore configurée.</p>`:''}${!reset&&!verify?`<label class="field">Mot de passe<div class="password-field"><input name="password" type="password" required ${signup||newPass?'minlength="10"':''} autocomplete="${signup||newPass?'new-password':'current-password'}" placeholder="${signup||newPass?'10 caractères minimum':'Votre mot de passe'}"><button class="password-toggle" type="button" aria-label="Afficher le mot de passe">Voir</button></div></label>`:''}${!signup&&!reset&&!verify&&!newPass?'<button class="text-button forgot" type="button" data-auth="reset">Mot de passe oublié ?</button>':''}${errorBox}<button class="primary" type="submit">${signup?'Rejoindre l’univers':reset?'Envoyer le lien':verify?'Vérifier mon lien':newPass?'Enregistrer le mot de passe':'Accéder au commandement'}${icon('arrow')}</button></form><div class="auth-bottom">${reset||verify?'<button class="text-button" data-auth="login">Retour à la connexion</button>':newPass?'<span>Votre mot de passe n’est jamais stocké dans le jeu.</span>':'<span>Un empire. Douze mondes. Votre histoire.</span>'}${!verify&&!newPass?'<button class="text-button" data-auth="verify">J’ai reçu un lien par e-mail</button>':''}</div></section><footer class="auth-footer"><span>GALAXY SIMULATOR <b>/</b> ALPHA 0.2</span><span>Un univers qui continue de vivre en votre absence.</span></footer></main>`;
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
  const results=await Promise.all([db.from('profiles').select('*').eq('id',user.id).maybeSingle(),db.from('empires').select('id,season_id,player_id,treasury,maintenance_debt,grade,created_at').eq('player_id',user.id).order('created_at',{ascending:false}),db.from('seasons').select('*').eq('status','alpha').maybeSingle()]);
  if(version!==state.version)return;
  const failed=results.find(r=>r.error);if(failed){fatal(failed.error);return;}
  state.profile=results[0].data;state.season=results[2].data;
  state.empire=results[1].data.find(e=>e.season_id===state.season?.id) || null;
  if(!state.empire){onboarding();return;}
  const gameData=await Promise.all([
    db.from('planets').select('*').eq('owner_empire_id',state.empire.id).order('created_at'),
    db.rpc('my_clan'),db.from('clans').select('id,name').eq('season_id',state.empire.season_id).order('name').limit(500),db.rpc('galaxy_map'),db.rpc('economy_overview'),db.rpc('military_dashboard')
  ]);
  if(version!==state.version)return;
  const gameError=gameData.find(r=>r.error);if(gameError){fatal(gameError.error);return;}
  state.military=gameData[5].data;state.planets=state.military.planets;state.clan=gameData[1].data;state.clans=gameData[2].data;state.signals=gameData[3].data;state.economy=gameData[4].data;state.empire.treasury=state.economy.treasury;state.empire.maintenance_debt=state.economy.maintenance_debt;
  if(!state.signals.some(p=>p.id===state.selectedSignal))state.selectedSignal=state.planets[0]?.id||state.signals[0]?.id;
  state.active=Math.min(state.active,Math.max(0,state.planets.length-1));
  if(state.page==='trade'){
    if(!state.planets.some(p=>p.id===state.tradePlanetId))state.tradePlanetId=state.planets[state.active]?.id;
    const trade=await db.rpc('trade_dashboard',{p_planet_id:state.tradePlanetId});
    if(version!==state.version)return;if(trade.error){fatal(trade.error);return;}state.tradeData=trade.data;
  }
  renderGame();
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
async function signout(){const {error}=await db.auth.signOut();if(error){toast(errorText(error));return;}state.version++;Object.assign(state,{user:null,profile:null,empire:null,planets:[],auth:'login',recovery:false,page:'planets',clan:null,clans:[],signals:[],selectedSignal:null,economy:null,tradeData:null,tradePlanetId:null,military:null,militaryPlanetId:null});authView();}
const navigation=[['command','command','Commandement',false],['planets','planet','Planètes',false],['trade','trade','Commerce',false],['map','map','Carte galactique',false],['fleets','fleet','Armées & flottes',false],['research','research','Technologies',true]];
function renderGame(){
  const p=state.planets[state.active];
  app.innerHTML=`<div class="game-layout ${state.page==='map'?'map-mode':''}"><aside class="sidebar">${brand()}<div class="sidebar-sector"><span class="eyebrow">COMMANDANT</span><strong>${h(state.profile.username)}</strong><small>${h(state.season?.name||'Session terminée')}</small></div><nav aria-label="Navigation principale">${navigation.map(([key,ico,label,disabled])=>`<button data-page="${key}" ${disabled?'disabled title="Disponible dans une prochaine version"':''} class="nav-item ${state.page===key?'active':''}">${icon(ico)}<span>${label}</span>${disabled?'<span class="soon">À VENIR</span>':icon('chevron')}</button>`).join('')}</nav><div class="sidebar-bottom"><button class="nav-item ${state.page==='account'?'active':''}" data-page="account">${icon('user')}<span>Compte & clan</span></button><button class="nav-item ${state.page==='help'?'active':''}" data-page="help">${icon('help')}<span>Archives & aide</span></button><div class="server-status"><i></i> LIAISON ÉTABLIE <span>ALPHA 0.2</span></div></div></aside><div class="main-shell"><header class="topbar"><button class="commander" data-page="account"><span class="commander-avatar">${h(state.profile.username.charAt(0).toUpperCase())}</span><span><small>${h(state.empire.grade)}</small><b>${h(state.profile.username)}</b></span></button><button class="treasury" data-page="revenues"><span>TRÉSORERIE</span><strong>${number(state.empire.treasury)} <em>Þ</em></strong></button><div class="top-tools"><button class="icon-button" data-page="alerts" aria-label="Notifications et alertes">${icon('bell')}</button><button class="icon-button" data-page="fleets" aria-label="Armées et flottes" title="Armées et flottes">${icon('fleet')}</button><button class="top-link" disabled title="Civilisation · à venir">Civilisation</button><button class="top-link" data-page="help">Aide</button><span class="forum" title="Le forum sera développé ultérieurement">Forum <small>À VENIR</small></span><button class="icon-button" id="signout" aria-label="Se déconnecter">${icon('logout')}</button></div></header><main id="game-content">${state.page==='planets'?planetView(p):state.page==='command'?commandView():state.page==='account'?accountView():state.page==='trade'?tradePage():state.page==='map'?mapView():state.page==='fleets'?pageHeader('COMMANDEMENT MILITAIRE','Armées & flottes')+militaryView(state.military,state.militaryPlanetId,pendingMilitaryCommand()):state.page==='help'?helpView():state.page==='revenues'?revenueView():alertsView()}</main><footer class="game-footer"><span><i></i> DONNÉES SAUVEGARDÉES SUR LE SERVEUR</span><span>GALAXY SIMULATOR · UNIVERS ALPHA</span></footer></div></div>`;
  document.querySelectorAll('[data-page]').forEach(b=>b.onclick=()=>{if(b.dataset.page==='trade'){openTrade();return;}state.page=b.dataset.page;renderGame();window.scrollTo({top:0,behavior:'instant'});});
  document.querySelector('#signout').onclick=signout;
  document.querySelector('#refresh')?.addEventListener('click',async e=>{e.currentTarget.disabled=true;await loadPlayer();toast('Données actualisées.');});
  document.querySelectorAll('button[data-planet]').forEach(b=>b.onclick=()=>{state.active=Number(b.dataset.planet);renderGame();});
  document.querySelector('#avatar-form')?.addEventListener('submit',e=>{e.preventDefault();submit(e.currentTarget,uploadAvatar);});
  if(state.page==='account'){loadAvatar();bindClans();}
  document.querySelector('#planet-options-form')?.addEventListener('submit',savePlanetOptions);
  if(state.page==='map')bindMap();
  if(state.page==='trade')bindTrade();
  bindMilitary();
}
function pageHeader(kicker,title,subtitle=''){return `<div class="page-heading"><div><div class="eyebrow">${kicker}</div><h1>${title}</h1>${subtitle?`<p>${subtitle}</p>`:''}</div><button id="refresh" class="refresh" title="Actualiser depuis le serveur">${icon('refresh')}<span>Actualiser</span></button></div>`;}
function planetView(p){
  if(!p)return pageHeader('VOS MONDES','Aucune planète')+'<p class="empty">Aucune planète sous votre contrôle.</p>'+foreignPresenceView(state.military);
  const r=races[p.race],resource=resources[p.resource];
  return `${pageHeader('TERRITOIRES IMPÉRIAUX','Vos planètes','Chaque monde est le commencement d’une nouvelle histoire.')}<div class="planet-selector"><span>MONDES CONTRÔLÉS <b>${state.planets.length}<small> / 12</small></b></span><div class="planet-tabs">${state.planets.map((world,i)=>`<button data-planet="${i}" class="planet-tab ${i===state.active?'selected':''}"><img class="mini-planet-art" src="${planetArt(world.race+'_'+world.resource,true)}" alt="" width="40" height="40"><span>${h(planetLabel(world,state.clan))}<small>${i===0?'MONDE D’ORIGINE':'MONDE IMPÉRIAL'}</small></span>${icon('chevron')}</button>`).join('')}</div></div><section class="planet-hero" aria-labelledby="planet-name"><div class="orbital-grid" aria-hidden="true"></div><img class="planet-showcase" src="${planetArt(p.race+'_'+p.resource)}" alt="${h(p.name)}" width="768" height="768"><div class="planet-hero-top"><span class="pill"><i></i> SOUS VOTRE CONTRÔLE</span><span class="coords">X ${Math.round(p.x)} · Y ${Math.round(p.y)}</span></div><div class="planet-hero-copy"><div class="eyebrow">${state.active===0?'VOTRE MONDE D’ORIGINE':'DOMAINE IMPÉRIAL'}</div><h2 id="planet-name">${h(p.name)}${p.clan_tag_visible&&state.clan?` <span class="clan-tag">[${h(state.clan.name)}]</span>`:''}</h2><p>Un point de lumière.<br>Le berceau de votre empire.</p><div class="planet-traits"><span title="${h(r.effect)}">${badge('race',p.race,'trait-art')}<span>${r.name}<small>${r.description}</small></span></span><span title="${h(resource.effect)}">${badge('resource',p.resource,'trait-art')}<span>${resource.name}<small>${resource.description}</small></span></span></div></div><div class="hero-bottom"><span>${icon('shield')} ${p.governance==='conseil'?'Gouvernée par un Conseil':'Gouvernée par une Tyrannie'}</span><span>ARCHIVES PLANÉTAIRES <b>01</b></span></div></section><div class="planet-sections"><section class="stat-section"><div class="section-heading">${icon('user')}<h3>Population & civilisation</h3><span>01</span></div><div class="big-stat">${number(p.population)}<small>HABITANTS</small></div><div class="stat-row"><span>Niveau de civilisation</span><strong>${civilizationBadge()} ${p.civilization}</strong></div><div class="level-line" aria-hidden="true"><span></span></div><p class="section-note">Assimilation et croissance disponibles dans une prochaine version.</p></section><section class="stat-section"><div class="section-heading">${icon('trade')}<h3>Économie & commerce</h3><span>02</span></div><div class="big-stat">${p.trade_capacity}<small>CAPACITÉS CONSTRUITES / 200</small></div><div class="stat-row"><span>Ressource principale</span><strong>${badge('resource',p.resource)} ${resource.name}</strong></div><p class="section-note">${resource.effect}. Gérez vos capacités et liaisons dans Commerce.</p></section><section class="stat-section"><div class="section-heading">${icon('shield')}<h3>Garnison & gouvernance</h3><span>03</span></div><div class="big-stat">${number(p.soldiers)}<small>SOLDATS EN GARNISON</small></div><div class="stat-row"><span>Vaisseaux stationnés</span><strong>${p.scouts+p.bombers+p.fighters}</strong></div><p class="section-note">${p.governance==='conseil'?'Conseil : croissance +20 % · production de soldats −20 %.':'Tyrannie : croissance −20 % · production de soldats +20 %.'} Recrutement : ${new Intl.NumberFormat('fr-FR',{maximumFractionDigits:2}).format(p.daily_recruits||0)} soldats / jour.</p><button class="text-button" data-page="fleets">Gérer les forces →</button></section><section class="stat-section"><div class="section-heading">${icon('sun')}<h3>Énergie & identité</h3><span>04</span></div><div class="big-stat">${p.energy}<span class="stat-max"> / ${p.energy_max}</span><small>RÉSERVE D’ÉNERGIE LOCALE</small></div><div class="stat-row"><span>Renommage initial</span><strong>${p.rename_available?'Disponible':'Utilisé'}</strong></div><p class="section-note">L’énergie nécessite une recherche. Désignation de la capitale à venir.</p></section></div>${planetOptions(p,state.clan)}${p.rename_available?`<form class="captured-rename" data-military="rename" data-planet="${h(p.id)}"><label class="field">Nommer cette planète<input name="name" minlength="3" maxlength="40" required></label><button class="secondary" type="submit">Choisir ce nom</button>${errorBox}</form>`:''}${foreignPresenceView(state.military)}<div class="alpha-banner"><span>ALPHA</span><p>Vos données et vos commandes sont sauvegardées. Consultez Commerce et Revenus pour développer vos échanges.</p></div>`;
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
function helpView(){return `${pageHeader('ARCHIVES IMPÉRIALES','Guide de l’alpha')}<article class="document-panel"><div class="eyebrow">VERSION 0.2 · CE QUI EST JOUABLE</div><h2>Le premier chapitre.</h2><p>Inscription, confirmation de l’e-mail, connexion, récupération du mot de passe, création de votre première planète, portrait du commandant, clans et tags planétaires sur la carte.</p><h3>Règles fixées</h3><p>Une session dure un an. Un empire vise au maximum douze planètes. La race et la ressource appartiennent à chaque planète. Le nom de la planète d’origine est choisi une seule fois à la fondation.</p><h3>Valeurs provisoires de l’alpha</h3><p>100 000 Þ de trésorerie, 1 000 000 d’habitants, civilisation 1, 100 soldats, aucun vaisseau, aucune capacité commerciale et 0/100 énergie. Les revenus civils et commerciaux ainsi que l’entretien des liaisons, soldats et vaisseaux sont actifs. La croissance reste à venir. Le recrutement est actif et peut être arrêté dans Armées & flottes.</p><p>L’univers commence avec 50 mondes. Chaque fondation ajoute 5 mondes, dont celui attribué au joueur. La carte expose les positions des signaux. Un monde extérieur sans tag conserve une désignation anonyme ; les propriétaires et les forces restent privés. L’apparence des mondes est publique ; les ressources sont visibles dans le commerce.</p><h3>Clans et commerce</h3><p>Vous pouvez créer ou rejoindre librement un clan. Chaque planète peut afficher son nom suivi de [Nom du clan], ou conserver son affiliation masquée. Quitter un clan masque tous vos tags ; un nouveau clan ne les réactive pas automatiquement.</p><p>Le commerce exige deux ressources différentes et des capacités disponibles aux deux extrémités. Le commerce automatique est activé par défaut pour chaque planète ; désactivez-le dans ses options pour examiner les futures demandes avant acceptation. Les demandes en attente réservent les capacités aux deux extrémités pendant 24 heures et ne produisent pas de revenus. Les liaisons actives rapportent aux deux planètes.</p><h3>Revenus et versements</h3><p>Revenus civils : 20 000 Þ par million d’habitants et par jour. Entretien journalier : 2 Þ par soldat, 20 Þ par scout, 60 Þ par bombardier et 80 Þ par chasseur. Une capacité occupée rapporte 1 500 Þ bruts par jour, moins un entretien de distance plafonné à 1 000 Þ : les liaisons proches sont plus rentables. La civilisation multiplie le rendement commercial net par 1 + 0,05 × (niveau − 1), jusqu’au niveau 40 (×2,95). Aurite ajoute 15 % après ce bonus et aux revenus civils.</p><p>Les versements ont lieu à 00 h, 08 h et 16 h UTC, même hors connexion. Seul le temps réellement écoulé depuis l’activation ou la fondation est comptabilisé. Les fractions de Þ sont conservées. Si les dépenses dépassent les fonds disponibles, un solde d’entretien à régulariser est remboursé par les prochains revenus ; les achats sont bloqués tant qu’il subsiste.</p><p>Le coût des capacités est progressif : environ un versement pour les vingt premières, puis 15 jours d’amortissement marginal de référence à la 50ᵉ et 60 jours à la 200ᵉ. Le rendement réel dépend de l’occupation, de la distance et des bonus. Une capacité inoccupée ne rapporte rien.</p><p>Les mondes neutres conservent 5 capacités, une population et une civilisation fixes, avec 1 scout et 1 soldat à l’initialisation. Leurs capacités disponibles sont partagées entre tous les joueurs.</p><h3>Races proposées</h3>${Object.values(races).map(r=>`<p><b><img class="art-badge" src="${r.art}" alt=""> ${r.name}</b> — ${r.effect}.</p>`).join('')}<h3>Ressources proposées</h3>${Object.values(resources).map(r=>`<p><b><img class="art-badge" src="${r.art}" alt=""> ${r.name}</b> — ${r.effect}.</p>`).join('')}<p>Les bonus militaires et industriels sont actifs pour les unités produites et les combats.</p>${militaryHelp}<h3>À venir</h3><p>Assimilation de civilisation, capitale, recherches et reconnaissance avancée. Le forum est indisponible.</p><h3>Illustration</h3><p>Illustrations de planètes, races, ressources et logo fournies par le créateur du jeu. Les blocs jaunes représentent des unités engagées, les blocs orange des centaines, et les blocs verts les capacités disponibles.</p></article>`;}
function revenueView(){return pageHeader('FINANCES IMPÉRIALES','Vos revenus','Des recettes et des dépenses réelles, comptabilisées par le serveur.')+revenuesView(state.economy);}
function pendingEconomicCommand(){try{return JSON.parse(sessionStorage.getItem('lw-economic-command:'+state.user.id)||'null');}catch{return null;}}
function tradePage(){return pageHeader('ROUTES & ÉCHANGES','Commerce','')+tradeView(state.tradeData,state.planets,state.empire.treasury,pendingEconomicCommand());}
async function openTrade(planetId){
  state.page='trade';state.tradePlanetId=planetId||state.planets[state.active]?.id;state.tradeData=null;renderGame();
  const id=state.tradePlanetId,version=state.version;
  try{const {data,error}=await db.rpc('trade_dashboard',{p_planet_id:id});if(error)throw error;if(version!==state.version||id!==state.tradePlanetId)return;state.tradeData=data;if(state.page==='trade')renderGame();}catch(error){toast(errorText(error));}
}
async function sendEconomicCommand(params,stored){
  const key='lw-economic-command:'+state.user.id;let pending=stored||pendingEconomicCommand();
  if(pending&&JSON.stringify(pending.params)!==JSON.stringify(params))throw Error('Reprenez d’abord la commande interrompue avec le bouton prévu.');
  if(!pending)pending={id:crypto.randomUUID(),params};sessionStorage.setItem(key,JSON.stringify(pending));
  const purchase=params.p_action==='buy',resize=params.resize===true;
  const {resize:omitResize,...command}=params;
  const args=purchase?{p_planet_id:params.p_planet_id,p_quantity:params.p_quantity,p_expected_capacity:params.expected_capacity,p_request_id:pending.id}:{...command,p_request_id:pending.id};
  const {data,error}=await db.rpc(purchase?'purchase_capacities':resize?'resize_trade':'trade_command',args);
  if(error){if(error.code)sessionStorage.removeItem(key);throw error;}
  sessionStorage.removeItem(key);return data;
}
function bindTrade(){
  const data=state.tradeData;if(!data)return;
  document.querySelector('#trade-world').onchange=e=>openTrade(e.target.value);
  updateTradeEstimates(data,state.empire.treasury);
  bindTradeDestinations(data,()=>updateTradeEstimates(data,state.empire.treasury));
  document.querySelectorAll('[data-resize-form]').forEach(form=>form.addEventListener('submit',event=>{
    event.preventDefault();const action=event.submitter?.value;if(!action)return;
    const link=data.links.find(l=>l.id===form.dataset.resizeForm);
    submit(form,async f=>{const result=await sendEconomicCommand({resize:true,p_action:action,p_planet_id:data.planet.id,p_link_id:link.id,p_quantity:Number(f.get('quantity')),p_expected_quantity:link.quantity});await loadPlayer();toast(result.status==='pending_increase'?'Ajout proposé. La liaison existante reste active.':'Capacités de la liaison mises à jour.');},event.submitter);
  }));
  document.querySelectorAll('[data-resize-action]').forEach(button=>button.onclick=async()=>{
    const link=data.links.find(l=>l.id===button.dataset.link);button.disabled=true;
    try{await sendEconomicCommand({resize:true,p_action:button.dataset.resizeAction,p_planet_id:data.planet.id,p_link_id:link.id,p_quantity:link.increase.quantity,p_expected_quantity:link.quantity});await loadPlayer();toast('Demande d’ajout mise à jour.');}catch(error){toast(errorText(error));}finally{button.disabled=false;}
  });
  document.querySelector('#buy-capacities')?.addEventListener('input',()=>updateTradeEstimates(data,state.empire.treasury));
  document.querySelector('#propose-trade')?.addEventListener('input',()=>updateTradeEstimates(data,state.empire.treasury));
  document.querySelector('#buy-capacities')?.addEventListener('submit',e=>{e.preventDefault();submit(e.currentTarget,async f=>{
    await sendEconomicCommand({p_action:'buy',p_planet_id:data.planet.id,p_quantity:Number(f.get('quantity')),expected_capacity:data.planet.capacity});
    await loadPlayer();toast('Capacités construites. Reliez-les à un autre monde pour générer des revenus.');
  });});
  document.querySelector('#propose-trade')?.addEventListener('submit',e=>{e.preventDefault();submit(e.currentTarget,async f=>{
    if(!f.get('target'))throw Error('Choisissez une planète de destination.');
    const result=await sendEconomicCommand({p_action:'propose',p_planet_id:data.planet.id,p_target_id:f.get('target'),p_quantity:Number(f.get('quantity'))});
    await loadPlayer();toast(result.status==='active'?'Liaison commerciale active.':'Demande envoyée. Les capacités sont réservées en attendant une décision.');
  });});
  document.querySelectorAll('[data-trade-action]').forEach(b=>b.onclick=async()=>{
    if(b.disabled)return;b.disabled=true;try{await sendEconomicCommand({p_action:b.dataset.tradeAction,p_link_id:b.dataset.link});await loadPlayer();toast('Liaison mise à jour.');}catch(error){toast(errorText(error));}finally{b.disabled=false;}
  });
  document.querySelector('#resume-economic-command')?.addEventListener('click',async e=>{
    const pending=pendingEconomicCommand();if(!pending)return;const button=e.currentTarget;button.disabled=true;
    try{await sendEconomicCommand(pending.params,pending);await loadPlayer();toast('Commande confirmée, sans nouvelle exécution en double.');}catch(error){toast(errorText(error));}finally{button.disabled=false;}
  });
}
function mapView(){return galaxyView(state.signals,state.selectedSignal,state.mapZoom);}
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
  document.querySelectorAll('[data-zoom]').forEach(b=>b.onclick=()=>{state.mapZoom=Math.min(3,Math.max(1,state.mapZoom+Number(b.dataset.zoom)*.5));renderGame();});
  document.querySelector('[data-open-planet]')?.addEventListener('click',e=>{const index=state.planets.findIndex(p=>p.id===e.currentTarget.dataset.openPlanet);if(index>=0){state.active=index;state.page='planets';renderGame();}});
}
function alertsView(){return pageHeader('TRANSMISSIONS','Notifications & rapports')+battleReportsView(state.military);}
function pendingMilitaryCommand(){try{return JSON.parse(sessionStorage.getItem('lw-military-command:'+state.user.id)||'null');}catch{return null;}}
async function sendMilitaryCommand(action,args,existing){
 const key='lw-military-command:'+state.user.id,payload={action,args};let pending=existing||pendingMilitaryCommand();
 if(pending&&JSON.stringify(pending.payload)!==JSON.stringify(payload))throw Error('Reprenez d’abord l’ordre interrompu.');
 if(!pending)pending={id:crypto.randomUUID(),payload};sessionStorage.setItem(key,JSON.stringify(pending));
 const {error}=await db.rpc('military_command',{p_action:action,p_args:args,p_request_id:pending.id});
 if(error){if(error.code)sessionStorage.removeItem(key);throw error;}
 sessionStorage.removeItem(key);await loadPlayer();toast('Ordre confirmé.');
}
function bindMilitary(){
 document.querySelector('#military-world')?.addEventListener('change',e=>{state.militaryPlanetId=e.target.value;renderGame();});
 const bindForms=root=>root.querySelectorAll('form[data-military]').forEach(form=>form.addEventListener('submit',e=>{
  e.preventDefault();submit(form,async fields=>{
   const args=Object.fromEntries(fields);if(form.dataset.planet)args.planet_id=form.dataset.planet;if(form.dataset.fleet)args.fleet_id=form.dataset.fleet;if(form.dataset.expectedFactories)args.expected_factories=Number(form.dataset.expectedFactories);
   for(const k of ['scouts','bombers','fighters','quantity','soldiers'])if(k in args)args[k]=Number(args[k]);if('enabled'in args)args.enabled=args.enabled==='true';
   await sendMilitaryCommand(form.dataset.military,args);
  });
 }));bindForms(document);
 document.querySelectorAll('[data-mission-fleet]').forEach(button=>button.addEventListener('click',()=>{
  const fleet=state.military.fleets.find(f=>f.id===button.dataset.missionFleet),panel=document.querySelector('#mission-orders');
  panel.hidden=false;panel.innerHTML=missionView(fleet,state.signals);bindMissionDestinations(panel,state.signals,fleet.planet_id);bindForms(panel);panel.querySelector('#close-mission').onclick=()=>{panel.hidden=true;};panel.scrollIntoView({behavior:matchMedia('(prefers-reduced-motion: reduce)').matches?'auto':'smooth',block:'nearest'});
 }));
 document.querySelector('#retry-military')?.addEventListener('click',async e=>{e.currentTarget.disabled=true;try{const p=pendingMilitaryCommand();if(p)await sendMilitaryCommand(p.payload.action,p.payload.args,p);}catch(error){toast(errorText(error));renderGame();}});
}
setInterval(()=>{document.querySelectorAll('[data-countdown]').forEach(el=>{el.textContent=timeLeft(el.dataset.countdown);});},30000);
setInterval(()=>{if(!state.user||!state.military||!['fleets','alerts','planets'].includes(state.page)||document.hidden||document.querySelector('form[aria-busy="true"]')||document.activeElement?.matches('input,select,textarea')||pendingMilitaryCommand())return;const due=[state.military.next_tick,...state.military.jobs.map(j=>j.finishes_at),...state.military.fleets.filter(f=>f.status==='transit').map(f=>f.arrives_at)];if(due.some(at=>new Date(at).getTime()<=Date.now()))loadPlayer();},60000);

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
