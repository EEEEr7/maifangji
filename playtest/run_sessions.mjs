// 夜市置业：100 局三角色试玩，截关键帧。不用 Studio MCP。
// 与 tools/autotest 同一套 XtappLuaRuntimeV2。
//
//   node maifangji/playtest/run_sessions.mjs
//   node maifangji/playtest/run_sessions.mjs --limit 3
import { mkdirSync, readFileSync, readdirSync, statSync, writeFileSync, copyFileSync, rmSync } from 'node:fs'
import { dirname, join } from 'node:path'
import { fileURLToPath, pathToFileURL } from 'node:url'
import { Worker as NodeWorker } from 'node:worker_threads'

const HERE = dirname(fileURLToPath(import.meta.url))
const ROOT = join(HERE, '..', '..')
const PROJECT = join(ROOT, 'maifangji')
const OUT = join(HERE, 'runs')
const UNIQUE = join(HERE, 'unique')
const RUNTIME = join(ROOT, 'xtapp-ai-studio', 'src', 'xtapp', 'runtime', 'v2')
const { XtappLuaRuntimeV2 } = await import(pathToFileURL(join(RUNTIME, 'runtimeV2.js')).href)
const { encodeGrayPng } = await import(pathToFileURL(join(RUNTIME, 'util', 'png.js')).href)

const SKIP = new Set([
  'playtest', 'art', 'xtapp-studio', 'tools', 'docs', 'node_modules',
  '.git', 'output', 'dist', 'preview', '__pycache__',
])

const TAP = {
  storyContinue: [377, 252],
  storyStart: [240, 252],
  startGame: [239, 748],
  confirmNew: [124, 574],
  cancelNew: [356, 574],
  help: [79, 748],
  helpNext: [402, 770],
  helpLeave: [77, 770],
  market1: [79, 620],
  market2: [239, 620],
  market3: [399, 620],
  bank: [59, 684],
  hospital: [179, 684],
  houses: [299, 684],
  agency: [419, 684],
  records: [399, 748],
  buy1: [75, 182],
  buy2: [75, 252],
  buy3: [75, 322],
  overlay: [240, 400],
  buyConfirm: [124, 598],
  buyClose: [356, 598],
  bankLeave: [356, 574],
  hospitalTreat: [178, 574],
  hospitalLeave: [302, 574],
  agencyLeave: [302, 589],
  housesBack: [52, 26],
  housesLeave: [380, 764],
  housesBuy: [100, 764],
  recordsBack: [52, 26],
  feedback: [240, 427],
}

function loadProject(dir) {
  const files = {}
  const walk = (abs, rel) => {
    for (const name of readdirSync(abs).sort()) {
      if (name.startsWith('.') || SKIP.has(name)) continue
      const full = join(abs, name)
      const key = rel ? `${rel}/${name}` : name
      if (statSync(full).isDirectory()) {
        walk(full, key)
        continue
      }
      if (name.endsWith('.lua') || name.endsWith('.json') || name.endsWith('.tsv')) {
        files[key] = readFileSync(full, 'utf8')
      } else if (name.endsWith('.xic') || name.endsWith('.png')) {
        files[key] = new Uint8Array(readFileSync(full))
      }
    }
  }
  walk(dir, '')
  for (const key of Object.keys(files)) {
    if (key.startsWith('assets/xic/')) files['assets/' + key.slice('assets/xic/'.length)] = files[key]
  }
  if (!files['manifest.json']) throw new Error(`${dir}: missing manifest.json`)
  return files
}

function createNodeWorker() {
  const worker = new NodeWorker(new URL(pathToFileURL(join(RUNTIME, 'worker.node.js')).href), { type: 'module' })
  const adapter = {
    onmessage: null,
    onerror: null,
    postMessage(message) { worker.postMessage(message) },
    terminate() { return worker.terminate() },
  }
  worker.on('message', (data) => adapter.onmessage?.({ data }))
  worker.on('error', (error) => adapter.onerror?.({ message: error.message, error }))
  return adapter
}

async function boot(model) {
  const files = loadProject(PROJECT)
  const manifest = JSON.parse(files['manifest.json'])
  const logs = []
  const runtime = new XtappLuaRuntimeV2({
    model,
    orientation: manifest.display?.orientation || 'portrait',
    locale: 'zh',
    files,
    storage: {},
    autoTick: false,
    workerFactory: createNodeWorker,
    onLog: (level, line) => logs.push({ level, line }),
  })
  await runtime.start(files['index.lua'], 'index.lua')
  for (let i = 0; i < 400 && !(await runtime.draw())?.session?.rgba; i += 1) {
    await new Promise((r) => setTimeout(r, 10))
  }
  return { runtime, manifest, logs }
}

async function grab(runtime) {
  for (let i = 0; i < 25; i += 1) {
    const snap = await runtime.draw()
    const s = snap?.session
    if (s?.rgba) return { rgba: Buffer.from(s.rgba), width: s.width, height: s.height }
    await runtime.tick(40)
    await new Promise((r) => setTimeout(r, 20))
  }
  throw new Error('no pixels')
}

function fingerprint(shot) {
  const { rgba, width, height } = shot
  let black = 0
  let acc = 0
  const step = Math.max(1, Math.floor(rgba.length / 4096))
  for (let i = 0; i < rgba.length; i += 4 * step) {
    const v = rgba[i]
    if (v < 40) black += 1
    acc = (acc * 33 + v) >>> 0
  }
  return `${width}x${height}-${black}-${acc.toString(16)}`
}

async function savePng(shot, path) {
  const png = await encodeGrayPng(shot.rgba, shot.width, shot.height)
  mkdirSync(dirname(path), { recursive: true })
  writeFileSync(path, png)
  return png.length
}

async function tap(runtime, xy) {
  await runtime.touch({ x: xy[0], y: xy[1], gesture: 'tap' })
  // X4 Pro 无 OK 键，只能点。宿主 300ms 内同点算双击，Lua 只认 tap。
  await runtime.tick(360)
}

async function key(runtime, name) {
  await runtime.input(name)
  await runtime.tick(200)
}

async function dismiss(runtime, times = 4) {
  // 主界面未处理的 back 会退出到系统桌面，弹层只点卡片本身。
  for (let i = 0; i < times; i += 1) {
    await tap(runtime, [TAP.overlay[0] + (i % 3) * 24, TAP.overlay[1] + (i % 2) * 24])
  }
}

async function skipStory(runtime, classic) {
  if (classic) {
    for (let i = 0; i < 5; i += 1) await key(runtime, 'ok')
    return
  }
  for (let i = 0; i < 4; i += 1) await tap(runtime, TAP.storyContinue)
  await tap(runtime, TAP.storyStart)
}

async function startPlaying(runtime, classic) {
  if (classic) {
    // 未开局时买卖/市场/银行均禁用，焦点落在「帮助」；下一次就是「开始游戏」。
    await key(runtime, 'down')
    await key(runtime, 'ok')
    await key(runtime, 'ok')
  } else {
    await tap(runtime, TAP.startGame)
    await tap(runtime, TAP.confirmNew)
  }
  await dismiss(runtime, 6)
}

function sessionPlan(id) {
  if (id <= 34) return { role: 'pm', classic: false }
  if (id <= 67) return { role: 'gamer', classic: false }
  return { role: 'engineer', classic: id >= 91 }
}

async function playPm(runtime, id, shot) {
  if (id <= 5) {
    for (let i = 1; i < id; i += 1) await tap(runtime, TAP.storyContinue)
    await shot('story')
    return 'story-page'
  }
  await skipStory(runtime, false)
  await shot('main-empty')
  if (id <= 14) {
    const steps = id - 5
    await tap(runtime, TAP.help)
    await shot('help-1')
    for (let i = 1; i < steps; i += 1) {
      await tap(runtime, TAP.helpNext)
      await shot(`help-${i + 1}`)
    }
    return `help-step-${steps}`
  }
  await startPlaying(runtime, false)
  await shot('playing')
  if (id <= 18) {
    await tap(runtime, TAP.buy1)
    await shot('buy-overlay')
    await tap(runtime, TAP.buyClose)
    return 'buy-overlay'
  }
  if (id === 19) {
    await tap(runtime, TAP.bank)
    await shot('bank')
    await tap(runtime, TAP.bankLeave)
    return 'bank'
  }
  if (id === 20) {
    await tap(runtime, TAP.hospital)
    await shot('hospital')
    await tap(runtime, TAP.hospitalLeave)
    return 'hospital'
  }
  if (id === 21) {
    await tap(runtime, TAP.agency)
    await shot('agency')
    await tap(runtime, TAP.agencyLeave)
    return 'agency'
  }
  if (id === 22) {
    await tap(runtime, TAP.houses)
    await shot('houses')
    await tap(runtime, TAP.housesBack)
    return 'houses'
  }
  if (id === 23) {
    await tap(runtime, TAP.records)
    await shot('records')
    await tap(runtime, TAP.recordsBack)
    return 'records'
  }
  if (id === 24) {
    await tap(runtime, TAP.market1)
    await shot('disabled-market')
    return 'disabled-current-market'
  }
  if (id <= 28) {
    await tap(runtime, TAP.market2)
    await dismiss(runtime, 5)
    await shot('market2')
    return 'switch-market2'
  }
  if (id <= 31) {
    await tap(runtime, TAP.startGame)
    await shot('quit-overlay')
    await tap(runtime, TAP.cancelNew)
    return 'quit-cancel'
  }
  await tap(runtime, TAP.help)
  for (let i = 0; i < 8; i += 1) await tap(runtime, TAP.helpNext)
  await shot('help-last')
  await tap(runtime, TAP.helpLeave)
  await shot('after-help')
  return 'help-complete'
}

async function playGamer(runtime, id, shot) {
  await skipStory(runtime, false)
  await startPlaying(runtime, false)
  await shot('week1')
  const n = ((id - 35) % 3)
  const markets = [TAP.market2, TAP.market3, TAP.market1]
  for (let w = 0; w < 2 + (id % 3); w += 1) {
    await tap(runtime, markets[(n + w) % 3])
    await dismiss(runtime, 5)
  }
  await shot('after-weeks')
  await tap(runtime, TAP.buy1)
  await shot('buy')
  await tap(runtime, TAP.buyConfirm)
  await tap(runtime, TAP.feedback)
  await tap(runtime, TAP.buyClose)
  await dismiss(runtime, 2)
  if (id % 4 === 0) {
    await tap(runtime, TAP.houses)
    await shot('houses')
    await tap(runtime, TAP.housesBuy)
    await tap(runtime, TAP.feedback)
    await tap(runtime, TAP.housesBack)
  } else if (id % 4 === 1) {
    await tap(runtime, TAP.hospital)
    await shot('hospital')
    await tap(runtime, TAP.hospitalTreat)
    await tap(runtime, TAP.feedback)
    await tap(runtime, TAP.hospitalLeave)
  } else if (id % 4 === 2) {
    await tap(runtime, TAP.bank)
    await shot('bank')
    await tap(runtime, TAP.bankLeave)
  } else {
    await tap(runtime, TAP.buy2)
    await shot('buy2')
    await tap(runtime, TAP.buyClose)
  }
  await shot('footer')
  return 'gamer-loop'
}

async function playEngineer(runtime, id, shot, classic) {
  if (classic) {
    await shot('classic-boot')
    await skipStory(runtime, true)
    await shot('classic-main')
    for (let i = 0; i < 14; i += 1) await key(runtime, 'down')
    await shot('classic-focus-walk')
    await key(runtime, 'ok')
    await shot('classic-help-or-action')
    for (let i = 0; i < 4; i += 1) await key(runtime, 'ok')
    await shot('classic-after-ok')
    await tap(runtime, TAP.overlay)
    await startPlaying(runtime, true)
    await shot('classic-playing')
    return 'classic-keys'
  }
  await skipStory(runtime, false)
  await shot('pro-main')
  if (id <= 75) {
    await tap(runtime, TAP.help)
    await shot('help-mask')
    await tap(runtime, TAP.helpLeave)
    await shot('help-leave')
    await tap(runtime, TAP.help)
    await tap(runtime, [240, 400])
    await shot('help-tap-mask-center')
    await tap(runtime, TAP.helpNext)
    await shot('help-next')
    return 'help-hit-test'
  }
  if (id <= 82) {
    await startPlaying(runtime, false)
    await shot('playing')
    await tap(runtime, TAP.buy1)
    await shot('overlay-open')
    await tap(runtime, TAP.market2)
    await shot('tap-through-overlay')
    await tap(runtime, TAP.buyClose)
    return 'overlay-block'
  }
  await startPlaying(runtime, false)
  await tap(runtime, TAP.market2)
  await dismiss(runtime, 5)
  await tap(runtime, TAP.market3)
  await dismiss(runtime, 5)
  await shot('after-two-markets')
  await tap(runtime, TAP.houses)
  await shot('houses')
  await tap(runtime, TAP.housesLeave)
  await shot('houses-leave')
  return 'engineer-nav'
}

async function runOne(id) {
  const { role, classic } = sessionPlan(id)
  const model = classic ? 'x4_classic' : 'x4_pro'
  const dir = join(OUT, String(id).padStart(3, '0'))
  mkdirSync(dir, { recursive: true })
  const host = await boot(model)
  const shots = []
  const shot = async (name) => {
    const frame = await grab(host.runtime)
    const file = join(dir, `${name}.png`)
    await savePng(frame, file)
    shots.push({ name, file, fp: fingerprint(frame) })
  }
  let goal = ''
  try {
    await shot('boot')
    if (role === 'pm') goal = await playPm(host.runtime, id, shot)
    else if (role === 'gamer') goal = await playGamer(host.runtime, id, shot)
    else goal = await playEngineer(host.runtime, id, shot, classic)
  } catch (error) {
    writeFileSync(join(dir, 'error.txt'), String(error && error.stack || error), 'utf8')
    goal = 'error'
  } finally {
    await Promise.race([host.runtime.dispose().catch(() => {}), new Promise((r) => setTimeout(r, 2000))])
  }
  const log = {
    id,
    role,
    model,
    goal,
    shots: shots.map((s) => ({ name: s.name, file: s.file.replace(HERE, 'playtest'), fp: s.fp })),
    luaLogs: host.logs.slice(-20),
  }
  writeFileSync(join(dir, 'log.json'), JSON.stringify(log, null, 2), 'utf8')
  return { ...log, _shots: shots }
}

const args = process.argv.slice(2)
const limitFlag = args.indexOf('--limit')
const startFlag = args.indexOf('--start')
const limit = limitFlag >= 0 ? Number(args[limitFlag + 1]) : 100
const start = startFlag >= 0 ? Number(args[startFlag + 1]) : 1
const end = Math.min(100, start + limit - 1)

if (limit >= 100) {
  rmSync(OUT, { recursive: true, force: true })
  rmSync(UNIQUE, { recursive: true, force: true })
}
mkdirSync(OUT, { recursive: true })
mkdirSync(UNIQUE, { recursive: true })

const summary = []
const seen = new Map()
const t0 = Date.now()
for (let id = start; id <= end; id += 1) {
  const t = Date.now()
  process.stderr.write(`[session] ${id}/${end} ${sessionPlan(id).role}\n`)
  const result = await runOne(id)
  for (const s of result._shots || []) {
    if (!seen.has(s.fp)) {
      seen.set(s.fp, s)
      const dest = join(UNIQUE, `${String(seen.size).padStart(3, '0')}-${result.role}-${s.name}.png`)
      copyFileSync(s.file, dest)
      seen.get(s.fp).unique = dest
    }
  }
  summary.push({
    id: result.id,
    role: result.role,
    model: result.model,
    goal: result.goal,
    shots: result.shots,
    ms: Date.now() - t,
    error: result.goal === 'error',
  })
}

const report = {
  at: new Date().toISOString(),
  htmlVm: 'maifangji/playtest/yehshi-device.html',
  sessions: summary.length,
  uniqueFrames: seen.size,
  elapsedMs: Date.now() - t0,
  roles: {
    pm: summary.filter((s) => s.role === 'pm').length,
    gamer: summary.filter((s) => s.role === 'gamer').length,
    engineer: summary.filter((s) => s.role === 'engineer').length,
  },
  errors: summary.filter((s) => s.error).map((s) => s.id),
  unique: [...seen.values()].map((s) => s.unique),
  sessionsDetail: summary,
}
writeFileSync(join(HERE, 'sessions.json'), JSON.stringify(report, null, 2), 'utf8')
console.log(`sessions=${summary.length} unique=${seen.size} errors=${report.errors.length} ms=${report.elapsedMs}`)
console.log(`unique dir: ${UNIQUE}`)
process.exit(report.errors.length ? 1 : 0)
