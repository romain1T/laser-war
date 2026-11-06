import { test } from 'node:test';
import assert from 'node:assert/strict';
import { escapeHtml, validateFounding, readEmailLink } from '../dist/domain.js';
test('Player-supplied names cannot inject HTML',()=>{
  assert.equal(escapeHtml('<img src=x onerror="alert(1)">'), '&lt;img src=x onerror=&quot;alert(1)&quot;&gt;');
});
test('Founding rejects empty and invalid identifiers',()=>{
  assert.ok(validateFounding({username:'a b',empire:'Orion',planet:'Nova'}));
  assert.ok(validateFounding({username:'Orion',empire:'  ',planet:'Nova'}));
  assert.equal(validateFounding({username:'Nova_1',empire:'Orion',planet:'Nova Prime'}),null);
});
test('Email verification accepts only the exact project endpoint',()=>{
  assert.deepEqual(readEmailLink('https://qidkgtuvcvoztzfmflgw.supabase.co/auth/v1/verify?token=example&type=recovery'),{token_hash:'example',type:'recovery'});
  for(const url of ['https://evil.example/auth/v1/verify?token=x&type=signup','javascript:alert(1)','https://qidkgtuvcvoztzfmflgw.supabase.co/auth/v1/verify?token=x&type=invite']) assert.throws(()=>readEmailLink(url));
});
