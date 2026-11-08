// Trusted setup for pre-existing teleport tests. Research timing and prerequisites
// are exercised separately in research-tree.test.mjs, without this fast-forward.
export async function researchFixture(db,q,args,id=crypto.randomUUID()){
 const {empire,planet,season}=await q('select e.id empire,p.id planet,e.season_id season from public.empires e join public.planets p on p.owner_empire_id=e.id where e.player_id=auth.uid() order by p.serial limit 1');
 if(args.technology==='teleport'){
  await q("insert into private.research_levels values($1,'energy',1,now()) on conflict do nothing",[empire]);
  await q('insert into private.player_technologies(empire_id,energy_unlocked_at) values($1,now()) on conflict(empire_id) do update set energy_unlocked_at=coalesce(private.player_technologies.energy_unlocked_at,excluded.energy_unlocked_at)',[empire]);
 }
 const result=(await q('select public.technology_command($1,$2,$3) result',['research',{...args,planet_id:planet},id])).result;
 await q("update private.research_jobs set finishes_at=now() where empire_id=$1 and completed_at is null and cancelled_at is null",[empire]);
 await q('select private.research_complete($1,now())',[season]);
 // These fixtures model the capabilities of accounts already funded before the
 // research tree rollout. Newly researched TP starts at 1/2 in the new tests.
 await q("insert into private.research_levels values($1,'energy_magma',1,now()) on conflict do nothing",[empire]);
 if(args.technology==='teleport')await q("insert into private.research_levels values($1,'teleport_improved',3,now()) on conflict do nothing",[empire]);
 return result;
}
