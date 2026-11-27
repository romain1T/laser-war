import test from 'node:test';
import assert from 'node:assert/strict';
import {militaryTestDatabase} from '../scripts/test-military-sql.mjs';

test('Real clustered geography bounds density and preserves fleet arrivals and planet identity',async()=>{
 let original,flight;
 const db=await militaryTestDatabase({beforeMigration:async(db,file)=>{
  if(!file.endsWith('_clustered_galactic_map.sql'))return;
  const uid='11111111-1111-4111-8111-111111111111';
  await db.query('insert into auth.users(id) values($1)',[uid]);
  await db.query("select set_config('request.jwt.claim.sub',$1,false)",[uid]);
  const e=(await db.query("select public.start_player('QA_Cluster','Cluster Prime') id")).rows[0].id;
  await db.exec(`insert into public.planets(season_id,race,resource) select (select id from public.seasons limit 1),'vael','aurite' from generate_series(1,greatest(0,136-(select count(*) from public.planets)::integer));`);
  const ps=(await db.query('select * from public.planets order by serial')).rows;
  const own=ps.find(p=>p.owner_empire_id===e),target=ps.find(p=>p.id!==own.id);
  const f=(await db.query(`insert into private.fleets(empire_id,season_id,name,race,supply_planet,origin_id,destination_id,status,scouts,route_x,route_y,departed_at,arrives_at)
   values($1,$2,'Transit','vael',$3,$3,$4,'transit',1,$5,$6,now()-interval '1 hour',now()+interval '10 hours') returning *`,[e,own.season_id,own.id,target.id,own.x,own.y])).rows[0];
  flight={...f,...(await db.query('select * from private.fleet_position((select f from private.fleets f where id=$1),now())',[f.id])).rows[0]};
  original=ps.map(p=>({id:p.id,name:p.name,owner:p.owner_empire_id}));
 }});
 try{
  const rows=(await db.query('select id,name,owner_empire_id owner,x,y from public.planets where destroyed_at is null order by serial')).rows;
  assert.deepEqual(rows.map(p=>({id:p.id,name:p.name,owner:p.owner})),original);
  const cells=new Map(),clusters=new Map();
  for(const p of rows){assert.ok(p.x>=0&&p.x<2000&&p.y>=0&&p.y<2000);const cell=`${Math.floor(p.x/50)},${Math.floor(p.y/50)}`,cluster=`${Math.floor(p.x/150)},${Math.floor(p.y/150)}`;cells.set(cell,(cells.get(cell)||0)+1);clusters.set(cluster,(clusters.get(cluster)||0)+1);}
  assert.equal(rows.length,136);assert.equal(clusters.size,11);
  assert.ok([...cells.values()].every(n=>n<=2));assert.ok([...clusters.values()].every(n=>n>=11&&n<=15));
  const f=(await db.query('select * from private.fleets where id=$1',[flight.id])).rows[0];
  assert.equal(f.arrives_at.getTime(),flight.arrives_at.getTime());assert.equal(f.scouts,1);
  assert.ok(Math.abs(f.route_x-flight.x*2)<.01);assert.ok(Math.abs(f.route_y-flight.y*2)<.01);
  await db.exec(`insert into public.planets(season_id,race,resource) select (select id from public.seasons limit 1),'vael','aurite' from generate_series(1,20);`);
  const maxCell=(await db.query('select max(n)::int n from (select count(*) n from public.planets where destroyed_at is null group by floor(x/50),floor(y/50))s')).rows[0].n;assert.equal(maxCell,2);
  const unchanged=(await db.query('select id,x,y from public.planets where id=any($1::uuid[]) order by serial',[rows.map(p=>p.id)])).rows;assert.deepEqual(unchanged,rows.map(({id,x,y})=>({id,x,y})));
  await db.exec(`set role authenticated;`);await assert.rejects(db.query('select private.place_clustered_planet()'));
 }finally{await db.close();}
});
