import { test } from 'node:test';
import assert from 'node:assert/strict';
import { escapeHtml, validateFounding, readEmailLink, planetLabel } from '../dist/domain.js';
test('Player-supplied names cannot inject HTML',()=>{
  assert.equal(escapeHtml('<img src=x onerror="alert(1)">'), '&lt;img src=x onerror=&quot;alert(1)&quot;&gt;');
});
test('Founding rejects empty and invalid identifiers',()=>{
  assert.ok(validateFounding({username:'a b',planet:'Nova'}));
  assert.ok(validateFounding({username:'Orion',planet:'  '}));
  assert.equal(validateFounding({username:'Nova_1',planet:'Nova Prime'}),null);
});
test('Clan labels are opt-in and do not rewrite the stored planet name',()=>{
  const planet={name:'Nova Prime',clan_tag_visible:false};
  assert.equal(planetLabel(planet,{name:'Veilleurs'}),'Nova Prime');
  assert.equal(planetLabel({...planet,clan_tag_visible:true},{name:'Veilleurs'}),'Nova Prime [Veilleurs]');
  assert.equal(planetLabel({...planet,clan_tag_visible:true},null),'Nova Prime');
  assert.equal(planet.name,'Nova Prime');
});
test('Email verification accepts only the exact project endpoint',()=>{
  assert.deepEqual(readEmailLink('https://qidkgtuvcvoztzfmflgw.supabase.co/auth/v1/verify?token=example&type=recovery'),{token_hash:'example',type:'recovery'});
  for(const url of ['https://evil.example/auth/v1/verify?token=x&type=signup','javascript:alert(1)','https://qidkgtuvcvoztzfmflgw.supabase.co/auth/v1/verify?token=x&type=invite']) assert.throws(()=>readEmailLink(url));
});
