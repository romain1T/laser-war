import test from 'node:test';
import assert from 'node:assert/strict';
import {destinationChoices,tradeView,capacityBlocks,planetTradeLabel} from '../dist/economy.js';
test('Nearest list has fifteen entries and named search reaches a distant world',()=>{
 const destinations=Array.from({length:30},(_,i)=>({id:String(i),name:`Monde ${i}`,available:5,distance:i}));
 assert.deepEqual(destinationChoices(destinations).map(d=>d.id),Array.from({length:15},(_,i)=>String(i)));
 assert.deepEqual(destinationChoices(destinations,'MONDE 29').map(d=>d.id),['29']);
 const crowded=Array.from({length:25},(_,i)=>({id:String(i),name:'Monde 1'+i})).concat({id:'exact',name:'Monde 1'});
 assert.equal(destinationChoices(crowded,'Monde 1')[0].id,'exact');
 const html=tradeView({planet:{id:'own',capacity:0,occupied:0,reserved:0},destinations,prices:[],links:[],enabled:true},[{id:'own',name:'Origine'}],0,null);
 assert.match(html,/data-destination="0"/);
 assert.doesNotMatch(html,/data-destination="15"/);
 assert.match(html,/<strong class="available-capacity">\+5<\/strong>/);
 assert.match(html,/Civ\. 1/);
});
test('Capacity blocks retain exact counts at hundred boundaries without visible digits',()=>{
 for(const count of [0,1,9,10,39,99,100,103,199,200]){
  const html=capacityBlocks(count,'engaged');
  const total=[...html.matchAll(/data-units="(\d+)"/g)].reduce((sum,m)=>sum+Number(m[1]),0);
  assert.equal(total,count);
  assert.equal((html.match(/class="capacity-block/g)||[]).length,Math.floor(count/100)+count%100);
  assert.doesNotMatch(html,/>\d+</);
 }
 assert.match(capacityBlocks(100,'engaged'),/engaged hundred/);
 assert.doesNotMatch(planetTradeLabel({name:'<script>',available:5,civilization:40}),/<script>/);
});
