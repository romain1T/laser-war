import {PGlite} from '@electric-sql/pglite';
import {readFile,readdir} from 'node:fs/promises';
import assert from 'node:assert/strict';
export async function militaryTestDatabase(){
 const db=new PGlite();await db.exec(`create role anon;create role authenticated;create schema auth;create schema storage;create schema cron;
 create table auth.users(id uuid primary key,email_confirmed_at timestamptz default now());
 create function auth.uid() returns uuid language sql as $$select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid$$;
 grant usage on schema auth to authenticated;grant execute on function auth.uid() to authenticated;
 create table storage.buckets(id text primary key,name text,public boolean,file_size_limit bigint,allowed_mime_types text[]);
 create table storage.objects(bucket_id text,name text);alter table storage.objects enable row level security;
 create function cron.schedule(text,text,text) returns bigint language sql as $$select 1::bigint$$;`);
 for(const file of (await readdir('supabase/migrations')).filter(f=>f.endsWith('.sql')).sort()){
  const sql=(await readFile('supabase/migrations/'+file,'utf8')).replace('create extension if not exists pg_cron;','');
  try{await db.exec(sql);}catch(error){console.error('Migration failed:',file);throw error;}
 }
 await db.exec(`update private.economy_clock set enabled=true;`);return db;
}
if(process.argv[1]?.endsWith('test-military-sql.mjs')){
 const db=await militaryTestDatabase();
 const uid='11111111-1111-4111-8111-111111111111';
 await db.query('insert into auth.users(id) values($1)',[uid]);await db.query("select set_config('request.jwt.claim.sub',$1,false)",[uid]);
 const [{rows}]=await db.exec("select public.start_player('QA_Military_Alpha','Alpha Prime') empire");const empire=rows[0].empire;
 const p=(await db.query('select * from public.planets where owner_empire_id=$1',[empire])).rows[0];
 console.log('Founded',p.name,'factories',p.factories);
 const command=async(action,args,id=crypto.randomUUID())=>(await db.query('select public.military_command($1,$2::jsonb,$3) result',[action,JSON.stringify(args),id])).rows[0].result;
 assert.equal(p.factories,5);assert.equal(p.soldiers,100);
 await db.exec('select private.economy_process()');
 const dashboard=async()=>(await db.query('select public.military_dashboard() result')).rows[0].result;
 const d=await dashboard();assert.equal(d.planets.length,1);assert.ok(d.planets[0].daily_recruits>=1&&d.planets[0].daily_recruits<=2);
 const req=crypto.randomUUID(),args={planet_id:p.id,kind:'scout',quantity:2};await command('ship',args,req);await command('ship',args,req);assert.equal((await dashboard()).jobs.length,2);
 await assert.rejects(command('ship',{...args,quantity:4}),/usines libres/);
 await db.query("update private.ship_jobs set finishes_at=now()-interval '1 minute' where empire_id=$1",[empire]);await db.exec('select private.economy_process()');
 assert.equal((await dashboard()).planets[0].scouts,2);
 const fleet=(await command('assemble',{planet_id:p.id,name:'Avant-garde',scouts:1,bombers:0,fighters:0})).id;
 await assert.rejects(command('load',{fleet_id:fleet,soldiers:1}),/Capacité/);
 const target=(await db.query('select * from public.planets where owner_empire_id is null limit 1')).rows[0];
 await command('dispatch',{fleet_id:fleet,target_id:target.id,mission:'attack'});assert.equal((await dashboard()).fleets[0].status,'transit');
 await db.query("update private.fleets set arrives_at=now()-interval '2 hours' where id=$1",[fleet]);await db.exec('select private.economy_process()');
 assert.equal((await dashboard()).presence.length,1);
 await db.query("select private.resolve_battle($1,now())",[target.id]);
 assert.ok((await dashboard()).reports.some(r=>r.event==='battle'));
 console.log('Core SQL flow passed');await db.close();
}
