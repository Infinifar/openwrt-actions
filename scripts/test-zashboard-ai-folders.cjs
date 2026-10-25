const assert = require('node:assert/strict')
const fs = require('node:fs')
const path = require('node:path')
const vm = require('node:vm')
const source = fs.readFileSync(path.join(__dirname, 'zashboard-ai-folders.js'), 'utf8')
function apply(initial) {
  const storage = new Map(Object.entries(initial))
  vm.runInNewContext(source, {
    localStorage: { getItem: key => storage.get(key) ?? null, setItem: (key, value) => storage.set(key, value) },
  })
  return Object.fromEntries(storage)
}
const key = 'config/proxy-folders'
let saved = apply({ 'unrelated-setting': 'preserve' })
let state = JSON.parse(saved[key])
assert(state.folders.find(folder => folder.id === 'builtin-strategy').manualIncludes.includes('AI'))
assert(state.folders.find(folder => folder.id === 'builtin-nodes').rules.some(rule => rule.pattern === '^AI$'))
assert.equal(saved['unrelated-setting'], 'preserve')
assert.deepEqual(apply(saved), saved, 'policy must be idempotent')
const custom = { id: 'custom-folder', name: 'Personal', rules: [], manualIncludes: ['Netflix'] }
const initial = {
  folders: [
    { id: 'builtin-strategy', manualIncludes: ['Google'], rules: [{ type: 'auto', value: 'hasGroup' }] },
    { id: 'builtin-nodes', manualIncludes: ['AI', 'US'], rules: [{ type: 'auto', value: 'nodeOnly' }] },
    custom,
  ], activeId: 'custom-folder', seeded: true,
}
saved = apply({ [key]: JSON.stringify(initial), 'config/secret': 'unchanged' })
state = JSON.parse(saved[key])
assert.equal(state.activeId, 'custom-folder')
assert.deepEqual(state.folders.find(folder => folder.id === 'custom-folder'), custom)
assert.deepEqual(state.folders.find(folder => folder.id === 'builtin-strategy').manualIncludes, ['Google', 'AI'])
assert.deepEqual(state.folders.find(folder => folder.id === 'builtin-nodes').manualIncludes, ['US'])
assert.equal(saved['config/secret'], 'unchanged')
assert.deepEqual(apply({ [key]: 'bad-json' }), { [key]: 'bad-json' })
vm.runInNewContext(source, { localStorage: { getItem: () => { throw Error('blocked') } } })
console.log('Zashboard AI folder tests passed: placement, exclusion, idempotence, preservation and unavailable storage')
