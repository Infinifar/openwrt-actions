/* Local firmware preference only: AI belongs to Strategy, never Nodes.
 * No network requests, credentials, proxy selections, or other settings. */
(() => {
  'use strict'
  try {
    const key = 'config/proxy-folders'
    const previous = localStorage.getItem(key)
    const state = previous === null
      ? { folders: [], activeId: '__all__', seeded: false }
      : JSON.parse(previous)
    if (!state || !Array.isArray(state.folders)) return
    const strategyId = 'builtin-strategy'
    const nodesId = 'builtin-nodes'
    const makeFolder = (id, name, order, value) => ({
      id, name, order, rules: [{ type: 'auto', value }], manualIncludes: [],
    })
    if (!state.seeded && state.folders.length === 0) {
      state.folders.push(
        makeFolder(strategyId, 'folder_builtin_strategy', 0, 'hasGroup'),
        makeFolder(nodesId, 'folder_builtin_nodes', 1, 'nodeOnly'),
      )
    }
    let strategy = state.folders.find(folder => folder.id === strategyId)
    if (!strategy) {
      strategy = makeFolder(strategyId, 'folder_builtin_strategy', state.folders.length, 'hasGroup')
      state.folders.push(strategy)
    }
    if (!Array.isArray(strategy.manualIncludes)) strategy.manualIncludes = []
    if (!strategy.manualIncludes.includes('AI')) strategy.manualIncludes.push('AI')
    const nodes = state.folders.find(folder => folder.id === nodesId)
    if (nodes) {
      if (!Array.isArray(nodes.rules)) nodes.rules = []
      if (!nodes.rules.some(rule => rule.type === 'excludeRegex' && rule.pattern === '^AI$')) {
        nodes.rules.push({ type: 'excludeRegex', pattern: '^AI$' })
      }
      if (Array.isArray(nodes.manualIncludes)) {
        nodes.manualIncludes = nodes.manualIncludes.filter(name => name !== 'AI')
      }
    }
    state.seeded = true
    const next = JSON.stringify(state)
    if (next !== previous) localStorage.setItem(key, next)
  } catch (_) {
    // Private browsing or malformed storage must not prevent opening the UI.
  }
})()
