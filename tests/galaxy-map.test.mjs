import test from 'node:test';
import assert from 'node:assert/strict';
import {galaxyView,galaxyBackground,clanColor,MAP_SIZE,CELL_SIZE,CLUSTER_SIZE,MAP_HEIGHT,MAP_COLUMNS,MAP_ROWS} from '../dist/galaxy.js';
test('Every world displays civilization, tagged worlds alone display clan rings and selected traits',()=>{
 const signals=[{id:'a',designation:'Alpha',x:100,y:200,is_own:true,appearance:'elys_aurite',race:'elys',resource:'aurite',civilization:12,clan_name:'Astre',clan_color:'#aaccee'},
 {id:'b',designation:'Signal 2',x:400,y:500,appearance:'khar_ferros',race:'khar',resource:'ferros',civilization:40,clan_name:null,clan_color:null}];
 const html=galaxyView(signals,'b',1);
 assert.equal((html.match(/class="map-civilization"/g)||[]).length,2);
 assert.equal((html.match(/class="clan-ring"/g)||[]).length,1);
 assert.match(html,/--clan-color:#aaccee/);
 assert.match(html,/<dt>Race<\/dt>/);assert.match(html,/>Khar<\/dd>/);
 assert.match(html,/>Ferros<\/dd>/);assert.match(html,/<span class="civilization-value">40<\/span>/);
 assert.doesNotMatch(html,/<small>\/ 40<\/small>/);
 assert.match(html,/assets\/art\/civilization\.webp/);
 assert.doesNotMatch(galaxyBackground(),/class="galaxy-arm/);
 assert.equal(clanColor({...signals[0],clan_name:null}),null);
 assert.equal(clanColor({...signals[0],clan_color:'red;display:none'}),null);
 assert.equal(galaxyBackground(),galaxyBackground());
 assert.match(html,/translate\(200,400\)/);
});

test('Foreign named worlds display their names without a clan tag or selection',()=>{
 const html=galaxyView([{id:'foreign',designation:'Aube libre',x:100,y:200,appearance:'elys_aurite',civilization:1,is_own:false}],null,1);
 assert.match(html,/<text class="signal-name"[^>]*>Aube libre<\/text>/);
});


test('Twenty galaxies fill a compact five by four map with distinct deterministic appearances',()=>{
 const html=galaxyView([],null,1);
 assert.equal(MAP_SIZE,1500);assert.equal(MAP_HEIGHT,1200);
 assert.equal(MAP_COLUMNS*MAP_ROWS,20);assert.equal(CLUSTER_SIZE,3*CELL_SIZE);
 assert.equal((html.match(/class="galaxy-cluster"/g)||[]).length,20);
 assert.equal((html.match(/<symbol id="cluster-galaxy-/g)||[]).length,5);
 assert.equal(new Set(Array.from({length:5},(_,i)=>galaxyBackground(i))).size,5);
 assert.match(html,/width="1500" height="1200" fill="url\(#mapgrid\)"/);
 assert.match(html,/class="map-coordinate">15<\/text>/);assert.match(html,/1 case = 1 unité/);
 const detail=galaxyView([{id:'p',designation:'P',x:50,y:100,civilization:1}], 'p',1);
 assert.match(detail,/X 1.0 <span>·<\/span> Y 2.0/);
});
