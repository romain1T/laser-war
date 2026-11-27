import {forceLevelGroups,unitLevel} from './unit-levels.js';
import {escapeHtml as h,number} from './domain.js';
import {badge,shipArt} from './art.js';
import {sumForces,forceCamps} from './operations.js';
const units=[['soldiers','Soldats'],['scouts','Scouts'],['bombers','Bombardiers'],['fighters','Destroyers']];
export function detailForceSummary(location,owned){
 const p={...location,forces:(location.forces?.length?location.forces:owned?[{...owned,is_own:true,kind:'reserve',mission:'defend',ground_soldiers:owned.soldiers}]:[]).map(f=>({...f,soldiers:0}))},totals=forceCamps(p),side=p.stance==='attack'?'attack':'defend';
 const camps=[{key:'own',name:'Vous',match:f=>f.is_own},...(['allies','enemies'].filter(k=>units.some(([u])=>totals[k][u]>0)).map(key=>({key,name:p.stance==='mixed'?(key==='allies'?'Autres : défense':'Autres : attaque'):(key==='allies'?'Alliés':'Ennemis'),match:f=>!f.is_own&&(key==='allies'?f.mission===side:f.mission!==side)})))];
 const cells=(key,forces)=>camps.map(c=>sumForces(forces.filter(c.match))[key]);
 const cell=(value,i)=>`<span class="${camps[i].key} ${value?'':'zero'}">${number(value)}</span>`;
 return `<section class="detail-force-summary" style="--force-columns:${camps.length}"><div class="detail-panel-heading"><span class="eyebrow">FORCES PRÉSENTES</span><h2>Rapport de force</h2><small>Soldats au sol · vaisseaux en orbite</small></div><div class="detail-force-scroll"><div class="detail-force-grid detail-force-head"><span>Unités</span><span>Vous</span>${camps.slice(1).map(c=>`<span class="${c.key}">${h(c.name)}</span>`).join('')}</div>${units.map(([key,label])=>{const races=forceLevelGroups(p.forces,key,p.race).map(g=>({...g,values:cells(key,p.forces.filter(f=>(f.race||p.race)===g.race&&(f[key==='soldiers'?'army_tech':'ship_tech']??null)===g.level))}));return `<details class="detail-unit"><summary class="detail-force-grid"><span class="detail-unit-name"><i aria-hidden="true">›</i>${key==='soldiers'?badge('race',p.race):shipArt(p.race,key==='scouts'?'scout':key==='bombers'?'bomber':'fighter')}${label}</span>${camps.map(c=>totals[c.key][key]).map(cell).join('')}</summary><div class="detail-unit-races">${races.map(r=>`<div class="detail-force-grid"><span>${badge('race',r.race)}${h(r.race.charAt(0).toUpperCase()+r.race.slice(1))}${unitLevel(r.level)}</span>${r.values.map(cell).join('')}</div>`).join('')||'<p>Aucune unité présente.</p>'}</div></details>`;}).join('')}</div></section>`;
}
export function productionTotals(jobs,race){
 const counts=[['scout','Scout'],['bomber','Bombardier'],['fighter','Destroyer']].map(([kind,label])=>({kind,label,count:jobs.filter(j=>j.kind===kind).length})).filter(t=>t.count);
 return counts.length?`<div class="production-totals"><span class="production-label">En construction</span>${counts.map(t=>`<span>${shipArt(race,t.kind)}${t.label} <b>×${number(t.count)}</b></span>`).join('')}</div>`:'';
}
