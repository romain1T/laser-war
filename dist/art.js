import {escapeHtml as h} from './domain.js';
const raceKeys=['elys','vael','khar'],resourceKeys=['aurite','biomasse','ferros'];
export function planetArt(appearance,small=false){
 const [race,resource]=String(appearance||'').split('_');
 return raceKeys.includes(race)&&resourceKeys.includes(resource)?`/assets/art/${race}_${resource}${small?'-map':''}.webp`:null;
}
export function badge(kind,key,className='art-badge'){
 const keys=kind==='race'?raceKeys:kind==='resource'?resourceKeys:[];
 if(!keys.includes(key))return '';
 const name=key.charAt(0).toUpperCase()+key.slice(1);
 return `<img class="${h(className)}" src="/assets/art/${kind}_${key}.webp" alt="${name}" title="${name}" width="32" height="32" loading="lazy">`;
}
export const civilizationBadge=()=>'<img class="art-badge civilization-badge" src="/assets/art/civilization.webp" alt="Civilisation" width="30" height="30" loading="lazy">';
