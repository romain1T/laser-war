import {planetArt,badge} from './art.js';
import {escapeHtml as h,races,resources} from './domain.js';

const label=p=>`${p.designation}${p.clan_name?` [${p.clan_name}]`:''}`;
export const clanColor=p=>p.clan_name&&/^#[0-9a-f]{6}$/i.test(p.clan_color||'')?p.clan_color:null;
const civilization=p=>Math.max(1,Math.min(40,Math.floor(Number(p.civilization)||1)));
const noise=n=>{const x=Math.sin(n*127.1+31.7)*43758.5453;return x-Math.floor(x);};

function spiralPath(arm){
 return Array.from({length:100},(_,i)=>{
  const t=i/99,r=22+t*670,angle=arm*Math.PI/2+t*5.5;
  return `${i?'L':'M'}${(Math.cos(angle)*r).toFixed(1)},${(Math.sin(angle)*r).toFixed(1)}`;
 }).join(' ');
}

export function galaxyBackground(){
 const stars=Array.from({length:180},(_,i)=>{
  const x=-35+noise(i+1)*1070,y=-35+noise(i+301)*1070,r=.5+noise(i+701)*1.25;
  return `<circle class="galaxy-star" cx="${x.toFixed(1)}" cy="${y.toFixed(1)}" r="${r.toFixed(1)}" style="--star-delay:-${(noise(i+911)*30).toFixed(1)}s;--star-duration:${(8+noise(i+1011)*14).toFixed(1)}s"/>`;
 }).join('');
 const arms=[0,1,2,3].map(n=>`<path d="${spiralPath(n)}" class="galaxy-arm arm-${n}"/><path d="${spiralPath(n)}" class="galaxy-arm-thread"/>`).join('');
 const dust=Array.from({length:180},(_,i)=>{
  const t=noise(i+1501),r=22+t*650,a=(i%4)*Math.PI/2+t*5.5+(noise(i+1701)-.5)*.22;
  return `<circle cx="${(Math.cos(a)*r).toFixed(1)}" cy="${(Math.sin(a)*r).toFixed(1)}" r="${(.6+noise(i+1901)*1.3).toFixed(1)}" fill="${i%3?'#9ab8ed':'#ead2b0'}" opacity="${(.15+noise(i+2101)*.35).toFixed(2)}"/>`;
 }).join('');
 return `<g class="galaxy-backdrop" aria-hidden="true" pointer-events="none"><rect x="-45" y="-45" width="1090" height="1090" fill="#030813"/><ellipse cx="420" cy="500" rx="640" ry="380" fill="url(#galaxy-haze)" transform="rotate(-28 420 500)"/>${stars}<g transform="translate(500 500) rotate(-28) scale(1 .58)"><g class="galaxy-spiral">${arms}${dust}</g><ellipse rx="195" ry="150" fill="url(#galaxy-core)"/></g></g>`;
}

function planetSignal(p,selectedId){
 const color=clanColor(p),tagged=Boolean(p.clan_name),art=planetArt(p.appearance,true),side=p.x>730?-26:26;
 return `<g class="map-signal ${p.is_own?'is-own':''} ${tagged?'is-tagged':''} ${selectedId===p.id?'is-selected':''}" data-signal="${h(p.id)}" transform="translate(${p.x},${p.y})"${color?` style="--clan-color:${color}"`:''}><title>${h(label(p))} · Civilisation ${civilization(p)}</title>${tagged?'<circle class="clan-aura" r="25"/><circle class="clan-ring" r="20"/>':''}<circle class="signal-halo" r="24"/>${art?`<image class="map-planet-art" href="${art}" x="-15" y="-15" width="30" height="30"/>`:`<circle class="signal-core" r="5"/>`}<g class="map-civilization" transform="translate(-14 -39)"><rect width="28" height="18" rx="5"/><text class="civilization-level" x="14" y="13" text-anchor="middle">${civilization(p)}</text></g>${p.is_own||tagged||selectedId===p.id?`<text class="signal-name" x="${side}" y="-3" text-anchor="${side<0?'end':'start'}">${h(p.designation)}</text>${tagged?`<text class="signal-tag" x="${side}" y="13" text-anchor="${side<0?'end':'start'}">[${h(p.clan_name)}]</text>`:''}`:''}</g>`;
}

function signalDetails(p){
 const color=clanColor(p),race=p.race||String(p.appearance||'').split('_')[0],resource=p.resource||String(p.appearance||'').split('_')[1];
 return `<div class="signal-readout">${planetArt(p.appearance)?`<img class="signal-planet-art" src="${planetArt(p.appearance)}" alt="${h(p.designation)}" width="240" height="240" loading="lazy">`:''}<span class="eyebrow">${p.is_own?'VOTRE PLANÈTE':p.clan_name?'SIGNATURE PUBLIQUE':'SIGNAL NON IDENTIFIÉ'}</span><h3>${h(p.designation)}</h3>${p.clan_name?`<strong class="public-clan-tag"${color?` style="--clan-color:${color}"`:''}><i aria-hidden="true"></i>[${h(p.clan_name)}]</strong>`:''}<dl class="signal-facts"><div><dt>Race</dt><dd>${badge('race',race)}${h(races[race]?.name||'Inconnue')}</dd></div><div><dt>Ressource</dt><dd>${badge('resource',resource)}${h(resources[resource]?.name||'Inconnue')}</dd></div><div><dt>Civilisation</dt><dd><span class="civilization-value">${civilization(p)}</span><small>/ 40</small></dd></div></dl><div class="signal-coords">X ${Math.round(p.x)} <span>·</span> Y ${Math.round(p.y)}</div>${p.is_own?`<button class="secondary" data-open-planet="${h(p.id)}">Gérer cette planète →</button>`:''}</div>`;
}

export function galaxyView(signals,selectedId,zoom){
 const selected=signals.find(p=>p.id===selectedId);
 return `<section class="galaxy"><div class="galaxy-toolbar"><div class="map-legend"><span><i class="own-dot"></i>Vos mondes</span><span><i class="clan-dot"></i>Tag de clan</span><span><i></i>Sans tag</span></div><div class="map-zoom"><button data-zoom="-1" ${zoom<=1?'disabled':''} aria-label="Réduire la carte">−</button><span>${Math.round(zoom*100)} %</span><button data-zoom="1" ${zoom>=3?'disabled':''} aria-label="Agrandir la carte">+</button></div></div><div class="galaxy-body"><div class="galaxy-scroll" tabindex="0" aria-label="Carte galactique, faites défiler pour explorer"><svg class="galaxy-svg" style="width:${zoom*100}%;min-width:${zoom*440}px" viewBox="-45 -45 1090 1090" role="img" aria-label="Positions et civilisations des mondes de la session"><defs><radialGradient id="galaxy-haze"><stop stop-color="#57427e" stop-opacity=".38"/><stop offset=".45" stop-color="#294e70" stop-opacity=".23"/><stop offset="1" stop-color="#080e18" stop-opacity="0"/></radialGradient><radialGradient id="galaxy-core"><stop stop-color="#f0d8b0" stop-opacity=".34"/><stop offset=".2" stop-color="#bfa7db" stop-opacity=".2"/><stop offset=".65" stop-color="#7077c9" stop-opacity=".1"/><stop offset="1" stop-color="#6760af" stop-opacity="0"/></radialGradient><pattern id="mapgrid" width="100" height="100" patternUnits="userSpaceOnUse"><path d="M100 0H0V100" fill="none" stroke="#8aa8b4" stroke-opacity=".055" stroke-width="1"/></pattern></defs>${galaxyBackground()}<rect width="1000" height="1000" fill="url(#mapgrid)" pointer-events="none"/>${[0,200,400,600,800,1000].map(n=>`<text x="${n}" y="-15" class="map-coordinate">${n}</text><text x="-35" y="${n+4}" class="map-coordinate">${n}</text>`).join('')}${signals.map(p=>planetSignal(p,selectedId)).join('')}</svg></div><aside class="signal-info"><div class="eyebrow">OBSERVATOIRE GALACTIQUE</div><h2>Un ciel,<br> mille intentions.</h2><label class="field">Sélectionner un signal<select id="signal-select">${signals.map(p=>`<option value="${h(p.id)}" ${selectedId===p.id?'selected':''}>${h(label(p))}</option>`).join('')}</select></label>${selected?signalDetails(selected):''}</aside></div></section>`;
}
