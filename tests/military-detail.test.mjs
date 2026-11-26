import test from 'node:test';
import assert from 'node:assert/strict';
import {detailForceSummary,productionTotals} from '../dist/military-detail.js';
import {militaryView} from '../dist/military.js';
test('Detail totals combine stationed ships and ground soldiers, excluding embarked soldiers',()=>{
 const html=detailForceSummary({race:'elys',stance:'own',forces:[{kind:'reserve',is_own:true,race:'elys',ground_soldiers:10,scouts:4},{kind:'fleet',is_own:true,race:'vael',ground_soldiers:3,soldiers:200,scouts:1}]});
 assert.match(html,/>13<\/span>/);assert.match(html,/>5<\/span>/);assert.match(html,/race_vael.webp/);assert.doesNotMatch(html,/Réserves|En flotte|>Alliés<|>Ennemis<|>213</);
});
test('Production shows quantities by ship type without an individual queue',()=>{
 const html=productionTotals([{kind:'scout'},{kind:'scout'},{kind:'bomber'}],'elys');
 assert.match(html,/Scout <b>×2/);assert.match(html,/Bombardier <b>×1/);assert.doesNotMatch(html,/Destroyer|<ol|<time/);assert.equal(productionTotals([],'elys'),'');
});
test('Orbital roster owns the order panel and hides attack on own worlds',()=>{
 const planet={id:'p',name:'Prime',race:'elys',resource:'ferros',civilization:1,population:1000000,soldiers:4,scouts:3,bombers:0,fighters:0,factories:5};
 const fleet={id:'f',name:'SG-1',planet_id:'p',status:'stationed',mission:'defend',race:'elys',scouts:1,bombers:0,fighters:0,soldiers:0,ground_soldiers:0,own_location:true};
 const data={planets:[planet],jobs:[],fleets:[fleet]};const html=militaryView(data,'p');
 assert.match(html,/Flottes en orbite/);assert.equal((html.match(/id="mission-orders"/g)||[]).length,1);assert.doesNotMatch(html,/fleet-command-choice|fleet-command-center|Passer en attaque|production-queue/);
 assert.ok(html.indexOf('planet-paranoia')<html.indexOf('detail-force-summary'));
 fleet.own_location=false;assert.match(militaryView(data,'p'),/Passer en attaque/);
});
