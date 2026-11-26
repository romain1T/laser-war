import test from 'node:test';
import assert from 'node:assert/strict';
import {detailForceSummary,fleetCommandCenter} from '../dist/military-detail.js';
test('Military detail separates reserves and fleets, retains races and hides empty foreign camps',()=>{
 const p={race:'elys',stance:'own',forces:[{kind:'reserve',is_own:true,race:'elys',ground_soldiers:10,scouts:4},{kind:'fleet',is_own:true,race:'vael',ground_soldiers:3,soldiers:2,scouts:1}]};
 const html=detailForceSummary(p);
 assert.match(html,/Réserves/);assert.match(html,/En flotte/);assert.match(html,/>15<\/span>/);assert.match(html,/>10<\/span>/);assert.match(html,/race_vael.webp/);
 assert.match(html,/13 au sol · 2 embarqués/);assert.doesNotMatch(html,/>Alliés<|>Ennemis</);
});
test('Command center offers only formed ship fleets, escapes labels and contains one mission panel',()=>{
 const html=fleetCommandCenter([{id:'one',name:'<SG-1>',scouts:2,bombers:1,fighters:0},{id:'ground',name:'Ground',scouts:0,bombers:0,fighters:0}]);
 assert.match(html,/id="fleet-command-choice"/);assert.match(html,/&lt;SG-1&gt;/);assert.doesNotMatch(html,/value="ground"/);assert.equal((html.match(/id="mission-orders"/g)||[]).length,1);
 assert.match(fleetCommandCenter([]),/Constituez une flotte/);
});
