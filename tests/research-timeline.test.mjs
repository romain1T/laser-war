import test from 'node:test';
import assert from 'node:assert/strict';
import {researchGraphLayout,researchTreeView,researchAvailability} from '../dist/research-tree.js';
const make=(key,requires=[])=>({key,name:key,branch:'infrastructure',requires,level:0,max_level:3,effect:'Effet',next_cost:200,next_hours:36,prerequisites_met:true,eligible_planets:[{id:'p',busy:false}]});
test('Research graph flows left to right from real prerequisites and bounds every card',()=>{
 const catalog=[make('child',[{key:'root',level:1}]),make('root'),...Array.from({length:10},(_,i)=>make('free'+i))],g=researchGraphLayout(catalog,'infrastructure');
 assert.ok(g.positions.get('root').x<g.positions.get('child').x);assert.ok(g.width>1000);
 const boxes=[...g.positions.values()];for(let i=0;i<boxes.length;i++){assert.ok(boxes[i].x+240<=g.width);assert.ok(boxes[i].y+152<=g.height);for(let j=i+1;j<boxes.length;j++)assert.ok(Math.abs(boxes[i].x-boxes[j].x)>=240||Math.abs(boxes[i].y-boxes[j].y)>=152);}
});
test('Research inspector, quick launches and lab restrictions use actual availability',()=>{
 const c=make('teleport_improved'),world={id:'p',name:'<Prime>',race:'khar',resource:'ferros'},data={catalog:[c],planets:[world],research_jobs:[]};
 assert.equal(researchAvailability(c,data,199,'p').ready,false);assert.equal(researchAvailability(c,data,200,'p').ready,true);
 const html=researchTreeView(data,200,'p',{selected:c.key});assert.match(html,/tech-frieze-scroll/);assert.match(html,/data-tech-pan="next"/);assert.match(html,/data-research-select="teleport_improved"/);assert.match(html,/expected_level" value="1"/);assert.match(html,/3 soldats \/ énergie/);assert.doesNotMatch(html,/<Prime>/);
 const poor=researchTreeView(data,199,'p');assert.match(poor,/À financer/);assert.match(poor,/Trésorerie insuffisante/);
 c.eligible_planets=[];assert.match(researchTreeView(data,500,'p'),/Labo requis/);assert.equal(researchAvailability(c,data,500,'p').ready,false);
});
