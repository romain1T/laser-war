import {escapeHtml as h,number} from './domain.js';
const date=value=>new Intl.DateTimeFormat('fr-FR',{day:'numeric',month:'long',year:'numeric',timeZone:'Europe/Paris'}).format(new Date(value));
export function roundSummaryView(data){
 if(!data)return '<p class="round-unavailable">Aucune partie en cours.</p>';
 return `<div class="round-heading"><span class="eyebrow">PARTIE EN COURS</span><h2>Round n°${number(data.round)}</h2><span class="round-live"><i></i> En cours</span></div><div class="round-dates"><span>Début <time datetime="${h(data.starts_at)}">${date(data.starts_at)}</time></span><span>Fin <time datetime="${h(data.ends_at)}">${date(data.ends_at)}</time></span></div><dl class="round-counts">${[['players','Joueurs'],['planets','Planètes'],['clans','Clans']].map(([key,label])=>`<div><dt>${label}</dt><dd>${number(data[key])}</dd></div>`).join('')}</dl>`;
}
let cached,pending,loadedAt=0;
export async function loadRoundSummary(db){
 const paint=html=>{const box=document.querySelector('#public-round-summary');if(box)box.innerHTML=html;};
 if(loadedAt&&Date.now()-loadedAt<60000){paint(roundSummaryView(cached));return;}
 try{pending||=db.rpc('round_summary');const {data,error}=await pending;if(error)throw error;cached=data;loadedAt=Date.now();paint(roundSummaryView(data));}
 catch{paint('<p class="round-unavailable">Informations de la partie momentanément indisponibles.</p>');}
 finally{pending=null;}
}
