import {badge,planetArt,civilizationBadge} from './art.js';
import { escapeHtml as h, number, races, resources } from './domain.js';
const money=v=>`${new Intl.NumberFormat('fr-FR',{maximumFractionDigits:0}).format(Number(v)||0)} Þ`;
const time=v=>new Intl.DateTimeFormat('fr-FR',{dateStyle:'short',timeStyle:'short'}).format(new Date(v));
const label=p=>`${p.name}${p.clan_name?` [${p.clan_name}]`:''}`;
const errorBox='<p class="form-error" role="alert" hidden></p>';
export function revenuesView(economy,unreadDates=[]){
  if(!economy)return '<p class="empty">Chargement des finances…</p>';
  const totals=economy.planets.reduce((a,p)=>{for(const k of ['civil','trade','trade_cost','military','fleet','net'])a[k]=(a[k]||0)+Number(p[k]);return a;},{});
  return `<div class="economic-overview"><section class="balance-panel"><div class="eyebrow">TRÉSORERIE DISPONIBLE</div><div class="balance">${money(economy.treasury)}</div><p>${economy.enabled?`Prochain versement : <strong>${time(economy.next_payout_at)}</strong>`:'Activation économique en préparation.'}</p>${Number(economy.maintenance_debt)>0?`<p class="debt-note">Entretien à régulariser : ${money(economy.maintenance_debt)}. Les prochains revenus remboursent ce solde avant de reconstituer votre trésorerie.</p>`:''}</section><section class="daily-panel"><div class="eyebrow">SOLDE QUOTIDIEN</div><strong class="daily-net ${totals.net<0?'negative':''}">${totals.net>=0?'+':''}${money(totals.net)}</strong><p>Prévision avec vos populations, forces et liaisons actuelles. Le temps passé hors connexion est comptabilisé par le serveur.</p><button class="secondary" data-page="trade">Piloter le commerce →</button></section></div><section class="economic-table-section"><div class="section-heading"><h2>Revenus de vos mondes</h2><span>MONTANTS PAR JOUR</span></div><div class="economic-table-scroll"><table class="economic-table"><thead><tr><th>Planète</th><th>Revenus civils</th><th>Commerce brut + bonus</th><th>Entretien liaisons</th><th>Soldats</th><th>Vaisseaux</th><th>Solde</th></tr></thead><tbody>${economy.planets.map(p=>`<tr><th>${h(p.name)}</th><td>${money(p.civil)}</td><td>${money(p.trade)}</td><td class="expense">−${money(p.trade_cost)}</td><td class="expense">−${money(p.military)}</td><td class="expense">−${money(p.fleet)}</td><td class="net-cell ${Number(p.net)<0?'negative':''}">${money(p.net)}</td></tr>`).join('')}</tbody><tfoot><tr><th>Total</th><td>${money(totals.civil)}</td><td>${money(totals.trade)}</td><td>−${money(totals.trade_cost)}</td><td>−${money(totals.military)}</td><td>−${money(totals.fleet)}</td><td>${money(totals.net)}</td></tr></tfoot></table></div><p class="form-note">Le bonus Aurite de 15 % s’applique aux revenus civils et au rendement commercial après entretien des liaisons. Aucun coût industriel fictif n’est ajouté.</p></section><section class="payout-history"><div class="section-heading"><h2>Derniers versements</h2><span>TROIS FOIS PAR JOUR</span></div>${economy.history.length?`<ol>${economy.history.map(p=>`<li class="${unreadDates.some(at=>new Date(at).getTime()===new Date(p.payout_at).getTime())?'is-unread':''}"><time>${time(p.payout_at)}</time><span>${Number(p.net)>=0?'+':''}${money(p.net)}</span></li>`).join('')}</ol>`:'<p class="empty">Aucun versement depuis l’activation. Votre premier versement couvrira uniquement le temps réellement écoulé.</p>'}</section>`;
}
export function destinationChoices(destinations,query=''){
 const term=query.trim().toLocaleLowerCase('fr');
 const matches=destinations.filter(d=>!term||d.name.toLocaleLowerCase('fr').includes(term));
 if(term)matches.sort((a,b)=>Number(b.name.toLocaleLowerCase('fr')===term)-Number(a.name.toLocaleLowerCase('fr')===term));
 return matches.slice(0,15);
}
export function planetTradeLabel(p,showAvailable=true){
 return '<span class="destination-name">'+h(p.name)+'</span>'+(showAvailable?'<span class="destination-divider" aria-hidden="true">|</span><strong class="available-capacity">+'+Number(p.available||0)+'</strong>':'')+'<span class="destination-divider" aria-hidden="true">|</span><span class="destination-civ">Civ. '+Number(p.civilization||1)+'</span>'+badge('resource',p.resource,'resource-inline');
}
const destinationOptions=destinations=>destinations.map(d=>'<button class="destination-option" type="button" role="option" aria-selected="false" tabindex="-1" data-destination="'+h(d.id)+'">'+planetTradeLabel(d)+'</button>').join('');
export function capacityBlocks(count,state){
 count=Math.max(0,Math.min(200,Math.floor(Number(count)||0)));
 const hundreds=Math.floor(count/100),units=count%100;
 return Array.from({length:hundreds},()=>'<span class="capacity-block '+state+' hundred" data-units="100" aria-hidden="true"></span>').join('')+Array.from({length:units},()=>'<span class="capacity-block '+state+' unit" data-units="1" aria-hidden="true"></span>').join('');
}
function routeGraphic(l){
 if(l.status!=='active')return '';
 return `<div class="route-graphic target-capacity"><div class="capacity-track" role="img" aria-label="${h(l.name)} : ${l.quantity} capacités dans cette liaison, ${Number(l.available)||0} libres">${capacityBlocks(l.quantity,'engaged')}${capacityBlocks(l.available||0,'free')}</div><strong class="available-capacity">+${Number(l.available)||0}</strong></div>`;
}
export function tradeTargetIdentity(l){
 const art=planetArt(l.appearance||l.race+'_'+l.resource),population=l.population==null?'—':new Intl.NumberFormat('en',{notation:'compact',maximumFractionDigits:1}).format(Number(l.population));
 return `<div class="route-target">${art?`<img class="route-planet-art" src="${art}" alt="${h(l.name)}" width="100" height="100" loading="lazy">`:''}<div><span class="route-state ${l.status==='active'?'active':'pending'}">${l.status==='active'?'LIAISON ACTIVE':l.can_review?'DEMANDE À EXAMINER':'EN ATTENTE'}</span><h3>${h(label(l))}</h3><div class="route-target-traits"><span>${badge('race',l.race)}${h(races[l.race]?.name||'—')}</span><span>${badge('resource',l.resource)}${h(resources[l.resource]?.name||'—')}</span><span>${civilizationBadge()}${Number(l.civilization)||1}</span><span title="${number(l.population||0)} habitants">${badge('pop',l.race)}${population}</span></div><p>${l.quantity} capacités · distance ${number(Math.round(l.distance))}${l.expires_at?` · expiration ${time(l.expires_at)}`:''}</p></div></div>`;
}
function routeCapacityControls(l){
 if(l.status!=='active')return '';
 return `<div class="route-capacities">${l.increase?`<p class="increase-pending">+${l.increase.quantity} capacités en attente · expiration ${time(l.increase.expires_at)}</p><div class="increase-actions">${l.increase.can_review?`<button class="secondary" data-resize-action="accept" data-link="${h(l.id)}">Accepter l’ajout</button><button class="text-button" data-resize-action="decline" data-link="${h(l.id)}">Refuser l’ajout</button>`:`<button class="text-button" data-resize-action="withdraw" data-link="${h(l.id)}">Retirer la demande d’ajout</button>`}</div>`:''}<form data-resize-form="${h(l.id)}"><label class="field">Modifier la quantité<input aria-label="Quantité pour ${h(label(l))}" name="quantity" type="number" min="1" max="200" value="1" step="1" required></label><div class="capacity-buttons"><button class="secondary" type="submit" value="increase" ${l.increase?'disabled':''}>+ Ajouter</button><button class="secondary" type="submit" value="decrease">− Retirer</button></div>${errorBox}</form></div>`;
}
export function tradeView(data,planets,treasury,pending){
  if(!data)return '<div class="empty">Établissement des liaisons commerciales…</div>';
  const p=data.planet,available=p.capacity-p.occupied-p.reserved;
  return `<div class="trade-world-picker"><label class="field">Planète à gérer<select id="trade-world">${planets.map(w=>`<option value="${h(w.id)}" ${w.id===p.id?'selected':''}>${h(w.name)}</option>`).join('')}</select></label><div><strong>${p.occupied}<span> / ${p.capacity}</span></strong><small>CAPACITÉS OCCUPÉES</small></div><div><strong>${p.reserved}</strong><small>RÉSERVÉES EN ATTENTE</small></div><div><strong>${available}</strong><small>DISPONIBLES</small></div></div>${!data.enabled?'<p class="alpha-banner">L’économie est en cours de préparation. Les commandes seront disponibles après activation.</p>':''}${pending?`<section class="pending-command" role="status"><p>Une commande n’a pas reçu de confirmation. Reprenez-la avant d’en envoyer une autre pour éviter tout achat en double.</p><button id="resume-economic-command" class="secondary">Reprendre la commande</button><p class="form-error" hidden></p></section>`:''}<div class="trade-workbench compact-commerce"><section class="trade-purchase"><div class="eyebrow">DÉVELOPPEMENT COMMERCIAL</div><h2>Construire des capacités</h2>${data.prices.length?`<form id="buy-capacities"><label class="field">Capacités à construire<input name="quantity" type="number" min="1" max="${data.prices.length}" step="1" value="1" required></label><div class="purchase-quote"><span>Investissement</span><strong id="capacity-cost">${money(data.prices[0])}</strong></div>${errorBox}<button class="primary" type="submit" ${!data.enabled?'disabled':''}>Construire les capacités <span>→</span></button></form>`:'<p class="capacity-limit">Capacité maximale atteinte : 200.</p>'}</section><section class="trade-proposal"><div class="eyebrow">NOUVELLE LIAISON</div><h2>Nouvelle liaison</h2><form id="propose-trade"><div class="destination-picker"><label class="field">Rechercher une planète<input id="trade-search" type="search" placeholder="Nom d’une planète" autocomplete="off"></label><span id="destination-hint" class="sr-only" aria-live="polite"></span><span class="field-label" id="destination-label">Destination</span><input type="hidden" name="target" value=""><button type="button" id="destination-toggle" aria-haspopup="listbox" aria-expanded="false" aria-controls="destination-options" aria-labelledby="destination-label destination-selected"><span id="destination-selected">Choisir une planète</span><span aria-hidden="true">⌄</span></button><div id="destination-options" role="listbox" aria-label="Destinations" hidden>${destinationOptions(destinationChoices(data.destinations))}</div></div><label class="field">Capacités à engager<input name="quantity" type="number" min="1" max="${Math.max(1,available)}" step="1" value="1" required></label><div class="route-estimate" id="route-estimate">Choisissez une destination pour estimer le revenu de votre planète.</div>${errorBox}<button class="primary" type="submit" ${!data.enabled||available<1?'disabled':''}>Proposer la liaison <span>→</span></button></form></section></div><section class="trade-routes"><div class="section-heading"><h2>Vos liaisons</h2><span>${p.auto_trade?'ACCEPTATION AUTOMATIQUE':'VALIDATION MANUELLE'}</span></div>${data.links.length?`<div class="routes-list">${data.links.map(l=>`<article class="trade-route">${tradeTargetIdentity(l)}<div class="route-profit"><strong>${l.status==='active'?'+':''}${money(l.net_daily)}<small> / jour</small></strong><span>${l.status==='active'?'Revenu net pour votre planète':'Revenu potentiel après acceptation'}</span></div><div class="route-actions">${l.can_review?`<button class="secondary" data-trade-action="accept" data-link="${h(l.id)}">Accepter</button><button class="text-button" data-trade-action="decline" data-link="${h(l.id)}">Refuser</button>`:`<button class="text-button" data-trade-action="cancel" data-link="${h(l.id)}">${l.status==='active'?'Fermer la liaison':'Retirer la demande'}</button>`}</div>${routeGraphic(l)}${routeCapacityControls(l)}</article>`).join('')}</div>`:'<p class="empty">Aucune liaison pour ce monde.</p>'}</section>`;
}
export function updateTradeEstimates(data,treasury){
  const buy=document.querySelector('#buy-capacities');
  if(buy){const q=Number(buy.elements.quantity.value),valid=Number.isInteger(q)&&q>0&&q<=data.prices.length;const cost=valid?data.prices.slice(0,q).reduce((a,b)=>a+Number(b),0):null;document.querySelector('#capacity-cost').textContent=cost===null?'—':money(cost);buy.querySelector('[type=submit]').disabled=!data.enabled||!valid||cost>Number(treasury);}
  const form=document.querySelector('#propose-trade');
  if(form){const d=data.destinations.find(x=>x.id===form.elements.target.value),q=Number(form.elements.quantity.value);document.querySelector('#route-estimate').textContent=d&&Number.isInteger(q)&&q>0?`${money(q*d.net_per_capacity)} nets / jour · distance : ${money(q*d.distance_cost)} / jour.`:'Choisissez une destination pour estimer le revenu de votre planète.';}
}

export function bindTradeDestinations(data,onChange){
 const form=document.querySelector('#propose-trade'),picker=form.querySelector('.destination-picker'),search=form.querySelector('#trade-search'),toggle=form.querySelector('#destination-toggle'),list=form.querySelector('#destination-options');
 const close=()=>{list.hidden=true;toggle.setAttribute('aria-expanded','false');};
 const draw=()=>{
  const choices=destinationChoices(data.destinations,search.value),selected=form.elements.target.value;
  list.innerHTML=choices.length?destinationOptions(choices):'<p class="empty">Aucune planète trouvée.</p>';
  list.hidden=false;toggle.setAttribute('aria-expanded','true');
  for(const button of list.querySelectorAll('[data-destination]')){
   button.setAttribute('aria-selected',String(button.dataset.destination===selected));
   button.onclick=()=>{const d=data.destinations.find(d=>d.id===button.dataset.destination);form.elements.target.value=d.id;form.querySelector('#destination-selected').innerHTML=planetTradeLabel(d);close();toggle.focus();onChange();};
  }
  form.querySelector('#destination-hint').textContent=search.value.trim()?'Résultats par nom · 15 maximum.':'15 planètes les plus proches · recherche dans tout l’univers.';
 };
 toggle.onclick=()=>{if(list.hidden)draw();else close();};
 search.oninput=()=>draw();
 picker.addEventListener('keydown',event=>{
  if(event.key==='Escape'){close();toggle.focus();return;}
  if(!['ArrowDown','ArrowUp','Home','End'].includes(event.key))return;
  if(list.hidden)draw();const options=[...list.querySelectorAll('[data-destination]')];if(!options.length)return;
  event.preventDefault();let i=options.indexOf(document.activeElement);
  i=event.key==='Home'?0:event.key==='End'?options.length-1:event.key==='ArrowDown'?(i+1)%options.length:(i<0?options.length-1:(i-1+options.length)%options.length);
  options[i].focus();
 });
 picker.addEventListener('focusout',()=>setTimeout(()=>{if(!picker.contains(document.activeElement))close();},0));
}
