import {planetArt,badge,civilizationBadge} from './art.js';
import {escapeHtml as h,races,resources} from './domain.js';

const label=p=>`${p.designation}${p.clan_name?` [${p.clan_name}]`:''}`;
export const clanColor=p=>p.clan_name&&/^#[0-9a-f]{6}$/i.test(p.clan_color||'')?p.clan_color:null;
const civilization=p=>Math.max(1,Math.min(40,Math.floor(Number(p.civilization)||1)));
const noise=n=>{const x=Math.sin(n*127.1+31.7)*43758.5453;return x-Math.floor(x);};

export function galaxyBackground(){
 const stars=Array.from({length:160},(_,i)=>{
  const x=-35+noise(i+1)*1070,y=-35+noise(i+301)*1070,r=.45+noise(i+701)*1.1;
  return '<circle class="galaxy-star" cx="'+x.toFixed(1)+'" cy="'+y.toFixed(1)+'" r="'+r.toFixed(1)+'" style="--star-delay:-'+(noise(i+911)*30).toFixed(1)+'s;--star-duration:'+(8+noise(i+1011)*14).toFixed(1)+'s"/>';
 }).join('');
 // Unequal stellar streams, a scattered disk and short spurs; no repeated radial strokes.
 const streams=[{phase:.35,turn:5.1,extent:650,width:.44},{phase:3.8,turn:4.15,extent:580,width:.66},{phase:1.95,turn:3.4,extent:390,width:.94}];
 const dust=Array.from({length:1550},(_,i)=>{
  const stream=streams[i%3],disk=i%7<2,t=Math.pow(noise(i+1501),.72);
  const r=18+t*(disk?620:stream.extent)+(noise(i+1701)-.5)*(20+t*75);
  const angle=disk?noise(i+2101)*Math.PI*2:stream.phase+t*stream.turn+.2*Math.sin(t*13+stream.phase)+(noise(i+1901)-.5)*(stream.width+t*.48);
  const x=Math.cos(angle)*r+14*Math.sin(t*9),y=Math.sin(angle)*r;
  const size=.45+noise(i+2301)*1.55,opacity=(.1+noise(i+2501)*.5)*(1-.5*t);
  return '<circle class="galaxy-dust" cx="'+x.toFixed(1)+'" cy="'+y.toFixed(1)+'" r="'+size.toFixed(1)+'" fill="'+['#9cbdff','#d5e5ff','#8b91ed','#78b5f2'][i%4]+'" opacity="'+opacity.toFixed(2)+'"/>';
 }).join('');
 const clouds=Array.from({length:26},(_,i)=>{
  const stream=streams[i%3],t=.18+noise(i+3001)*.8,r=t*stream.extent,angle=stream.phase+t*stream.turn+.2*Math.sin(t*13+stream.phase);
  return '<ellipse cx="'+(Math.cos(angle)*r).toFixed(1)+'" cy="'+(Math.sin(angle)*r).toFixed(1)+'" rx="'+(45+noise(i+3201)*80).toFixed(1)+'" ry="'+(24+noise(i+3401)*50).toFixed(1)+'" fill="url(#galaxy-cloud-'+(i%3?'blue':'violet')+')" opacity="'+(.18+noise(i+3601)*.24).toFixed(2)+'"/>';
 }).join('');
 const core=Array.from({length:220},(_,i)=>{
  const r=Math.pow(noise(i+4001),1.4)*130,angle=noise(i+4201)*Math.PI*2;
  return '<circle cx="'+(Math.cos(angle)*r).toFixed(1)+'" cy="'+(Math.sin(angle)*r).toFixed(1)+'" r="'+(.4+noise(i+4401)).toFixed(1)+'" fill="#d2e7ff" opacity="'+(.12+noise(i+4601)*.48).toFixed(2)+'"/>';
 }).join('');
 return '<g class="galaxy-backdrop" aria-hidden="true" pointer-events="none"><rect x="-45" y="-45" width="1090" height="1090" fill="#030813"/><ellipse cx="460" cy="500" rx="650" ry="410" fill="url(#galaxy-haze)" transform="rotate(-28 460 500)"/>'+stars+'<g transform="translate(500 500) rotate(-28) scale(1 .58)"><g class="galaxy-spiral">'+clouds+dust+core+'</g><ellipse rx="165" ry="132" fill="url(#galaxy-core)"/></g></g>';
}

function planetSignal(p,selectedId){
 const color=clanColor(p),tagged=Boolean(p.clan_name),art=planetArt(p.appearance,true),side=p.x>730?-26:26;
 return `<g class="map-signal ${p.is_own?'is-own':''} ${tagged?'is-tagged':''} ${selectedId===p.id?'is-selected':''}" data-signal="${h(p.id)}" transform="translate(${p.x},${p.y})"${color?` style="--clan-color:${color}"`:''}><title>${h(label(p))} · Civilisation ${civilization(p)}</title>${tagged?'<circle class="clan-aura" r="25"/><circle class="clan-ring" r="20"/>':''}<circle class="signal-halo" r="24"/>${art?`<image class="map-planet-art" href="${art}" x="-15" y="-15" width="30" height="30"/>`:`<circle class="signal-core" r="5"/>`}<g class="map-civilization" transform="translate(-14 -39)"><rect width="28" height="18" rx="5"/><text class="civilization-level" x="14" y="13" text-anchor="middle">${civilization(p)}</text></g>${p.is_own||tagged||selectedId===p.id?`<text class="signal-name" x="${side}" y="-3" text-anchor="${side<0?'end':'start'}">${h(p.designation)}</text>${tagged?`<text class="signal-tag" x="${side}" y="13" text-anchor="${side<0?'end':'start'}">[${h(p.clan_name)}]</text>`:''}`:''}</g>`;
}

function signalDetails(p){
 const color=clanColor(p),race=p.race||String(p.appearance||'').split('_')[0],resource=p.resource||String(p.appearance||'').split('_')[1];
 return `<div class="signal-readout">${planetArt(p.appearance)?`<img class="signal-planet-art" src="${planetArt(p.appearance)}" alt="${h(p.designation)}" width="240" height="240" loading="lazy">`:''}<div class="signal-banner"><div class="signal-identity"><span class="eyebrow">${p.is_own?'VOTRE PLANÈTE':p.clan_name?'SIGNATURE PUBLIQUE':'SIGNAL NON IDENTIFIÉ'}</span><h3>${h(p.designation)}</h3>${p.clan_name?`<strong class="public-clan-tag"${color?` style="--clan-color:${color}"`:''}><i aria-hidden="true"></i>[${h(p.clan_name)}]</strong>`:''}</div><dl class="signal-facts"><div><dt>Race</dt><dd>${badge('race',race)}${h(races[race]?.name||'Inconnue')}</dd></div><div><dt>Ressource</dt><dd>${badge('resource',resource)}${h(resources[resource]?.name||'Inconnue')}</dd></div><div><dt>Civilisation</dt><dd>${civilizationBadge()}<span class="civilization-value">${civilization(p)}</span></dd></div></dl><div class="signal-coords">X ${Math.round(p.x)} <span>·</span> Y ${Math.round(p.y)}</div>${p.is_own?`<button class="secondary" data-open-planet="${h(p.id)}">Gérer cette planète →</button>`:''}</div></div>`;
}

export function galaxyView(signals,selectedId,zoom){
 const selected=signals.find(p=>p.id===selectedId);
 return `<section class="galaxy"><div class="galaxy-toolbar"><h1>Carte galactique</h1><div class="map-zoom"><button data-zoom="-1" ${zoom<=1?'disabled':''} aria-label="Réduire la carte">−</button><span>${Math.round(zoom*100)} %</span><button data-zoom="1" ${zoom>=3?'disabled':''} aria-label="Agrandir la carte">+</button></div></div><div class="galaxy-body"><div class="galaxy-scroll" tabindex="0" aria-label="Carte galactique, faites défiler pour explorer"><svg class="galaxy-svg" style="width:${zoom*100}%;min-width:${zoom*440}px" viewBox="-45 -45 1090 1090" role="img" aria-label="Positions et civilisations des mondes de la session"><defs><radialGradient id="galaxy-haze"><stop stop-color="#57427e" stop-opacity=".38"/><stop offset=".45" stop-color="#294e70" stop-opacity=".23"/><stop offset="1" stop-color="#080e18" stop-opacity="0"/></radialGradient><radialGradient id="galaxy-core"><stop stop-color="#eaf5ff" stop-opacity=".65"/><stop offset=".13" stop-color="#d6eaff" stop-opacity=".44"/><stop offset=".4" stop-color="#87b2ef" stop-opacity=".19"/><stop offset="1" stop-color="#6760af" stop-opacity="0"/></radialGradient><radialGradient id="galaxy-cloud-blue"><stop stop-color="#7eaff2" stop-opacity=".55"/><stop offset=".4" stop-color="#457bc4" stop-opacity=".2"/><stop offset="1" stop-color="#284273" stop-opacity="0"/></radialGradient><radialGradient id="galaxy-cloud-violet"><stop stop-color="#a194ed" stop-opacity=".4"/><stop offset=".45" stop-color="#6961ac" stop-opacity=".18"/><stop offset="1" stop-color="#332b61" stop-opacity="0"/></radialGradient><pattern id="mapgrid" width="100" height="100" patternUnits="userSpaceOnUse"><path d="M100 0H0V100" fill="none" stroke="#8aa8b4" stroke-opacity=".055" stroke-width="1"/></pattern></defs>${galaxyBackground()}<rect width="1000" height="1000" fill="url(#mapgrid)" pointer-events="none"/>${[0,200,400,600,800,1000].map(n=>`<text x="${n}" y="-15" class="map-coordinate">${n}</text><text x="-35" y="${n+4}" class="map-coordinate">${n}</text>`).join('')}${signals.map(p=>planetSignal(p,selectedId)).join('')}</svg></div><aside class="signal-info" aria-label="Planète sélectionnée">${selected?signalDetails(selected):''}</aside></div></section>`;
}
