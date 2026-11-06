import test from 'node:test';
import assert from 'node:assert/strict';
import {destinationChoices,tradeView} from '../dist/economy.js';
test('Nearest list has fifteen entries and named search reaches a distant world',()=>{
 const destinations=Array.from({length:30},(_,i)=>({id:String(i),name:`Monde ${i}`,available:5,distance:i}));
 assert.deepEqual(destinationChoices(destinations).map(d=>d.id),Array.from({length:15},(_,i)=>String(i)));
 assert.deepEqual(destinationChoices(destinations,'MONDE 29').map(d=>d.id),['29']);
 const html=tradeView({planet:{id:'own',capacity:0,occupied:0,reserved:0},destinations,prices:[],links:[],enabled:true},[{id:'own',name:'Origine'}],0,null);
 assert.match(html,/>Monde 0 \+5<\/option>/);
 assert.doesNotMatch(html,/>Monde 15 \+5<\/option>/);
 assert.doesNotMatch(html,/>Monde 0 ·/);
});
