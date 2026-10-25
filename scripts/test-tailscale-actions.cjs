'use strict';
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const source = fs.readFileSync(path.join(__dirname, '../user/common/tailscale/actions.js'), 'utf8');

async function scenario(options = {}) {
    const events = [], notes = [];
    let clock = 0, checks = 0;
    const sequence = [...(options.statuses || ['queued', 'running', 'success'])];
    const rpc = {declare(spec) {
        if (spec.method === 'setup_firewall') return async () => {
            events.push('setup');
            return options.setup || {success:true, queued:true};
        };
        return async () => {
            checks++;
            const next = sequence.length ? sequence.shift() : 'running';
            if (next === 'XHR') throw new Error('XHR request aborted by browser');
            return {status:next};
        };
    }};
    const uci = {changes:async () => { events.push('changes'); return options.pending || {}; }};
    const ui = {addNotification:(_a, content, kind) => notes.push({kind, message:content})};
    const window = {setTimeout(fn) { clock += options.tick || 1000; fn(); }};
    const actions = new Function('rpc','uci','ui','window','E','Date',source)(
        rpc, uci, ui, window, (_tag,_attr,text) => text, {now:() => clock});
    await actions.configureFirewall({save:async () => {
        events.push('save');
        if (options.invalid) throw new Error('invalid form');
    }});
    return {events, notes, checks};
}
(async () => {
    let r = await scenario();
    assert.deepEqual(r.events,['save','changes','setup']);
    assert.equal(r.notes.at(-1).kind,'info');
    assert.match(r.notes.at(-1).message,/已完成/);
    r = await scenario({statuses:['XHR','running','XHR','success']});
    assert.equal(r.checks,4);
    assert.match(r.notes.at(-1).message,/已完成/);
    for (const state of ['network_failed','firewall_failed','settings_failed','unknown']) {
        r = await scenario({statuses:[state]});
        assert.equal(r.notes.at(-1).kind,'error');
        assert.match(r.notes.at(-1).message,new RegExp(state));
        assert.equal(r.notes.some(n => /已完成/.test(n.message)),false);
    }
    r = await scenario({pending:{tailscale:[['set','settings','advertise_exit_node','1']]}});
    assert.equal(r.events.includes('setup'),false);
    assert.match(r.notes.at(-1).message,/保存并应用/);
    r = await scenario({invalid:true});
    assert.deepEqual(r.events,['save']);
    r = await scenario({setup:{error:'busy'}});
    assert.equal(r.checks,0);
    assert.match(r.notes.at(-1).message,/busy/);
    r = await scenario({setup:{success:true}});
    assert.equal(r.checks,0);
    assert.equal(r.notes.at(-1).kind,'error');
    r = await scenario({statuses:['XHR'],tick:180000});
    assert.equal(r.notes.at(-1).kind,'error');
    assert.match(r.notes.at(-1).message,/未能确认/);
    console.log('Tailscale LuCI actions: 11 success/failure/transport/pending/version/timeout cases passed');
})().catch(err => { console.error(err); process.exitCode = 1; });
