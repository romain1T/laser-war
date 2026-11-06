import test from 'node:test';
import assert from 'node:assert/strict';
import {galaxyView,galaxyBackground,clanColor} from '../dist/galaxy.js';
test('Every world displays civilization, tagged worlds alone display clan rings and selected traits',()=>{
 const signals=[{id:'a',designation:'Alpha',x:100,y:200,is_own:true,appearance:'elys_aurite',race:'elys',resource:'aurite',civilization:12,clan_name:'Astre',clan_color:'#aaccee'},
 {id:'b',designation:'Signal 2',x:400,y:500,appearance:'khar_ferros',race:'khar',resource:'ferros',civilization:40,clan_name:null,clan_color:null}];
 const html=galaxyView(signals,'b',1);
 assert.equal((html.match(/class="map-civilization"/g)||[]).length,2);
 assert.equal((html.match(/class="clan-ring"/g)||[]).length,1);
 assert.match(html,/--clan-color:#aaccee/);
 assert.match(html,/<dt>Race<\/dt>/);assert.match(html,/>Khar<\/dd>/);
 assert.match(html,/>Ferros<\/dd>/);assert.match(html,/<span class="civilization-value">40<\/span>/);
 assert.equal(clanColor({...signals[0],clan_name:null}),null);
 assert.equal(clanColor({...signals[0],clan_color:'red;display:none'}),null);
 assert.equal(galaxyBackground(),galaxyBackground());
 assert.match(html,/translate\(100,200\)/);
});
