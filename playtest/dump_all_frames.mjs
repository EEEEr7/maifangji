// 把夜市置业（买房记）当前代码能走到的画面全部截成 PNG，方便本地预览。
//
//   node maifangji/playtest/dump_all_frames.mjs
import { mkdirSync, readFileSync, readdirSync, rmSync, statSync, writeFileSync } from 'node:fs'
import { dirname, join } from 'node:path'
import { fileURLToPath, pathToFileURL } from 'node:url'
import { Worker as NodeWorker } from 'node:worker_threads'

const HERE = dirname(fileURLToPath(import.meta.url))
const ROOT = join(HERE, '..', '..')
const PROJECT = join(ROOT, 'maifangji')
const OUT = join(HERE, 'frames')
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
  cancelQuit: [356, 574],
  help: [79, 748],
  helpNext: [402, 770],
  helpLeave: [77, 770],
  market2: [239, 620],
  market3: [399, 620],
  bank: [59, 684],
  hospital: [179, 684],
  houses: [299, 684],
  agency: [419, 684],
  records: [399, 748],
  buy1: [75, 182],
  sell1: [307, 182],
  overlay: [240, 400],
  buyConfirm: [124, 598],
  buyClose: [356, 598],
  bankLeave: [356, 574],
  hospitalLeave: [302, 574],
  agencyLeave: [302, 589],
  housesLeave: [380, 764],
  recordsLeave: [240, 764],
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

async function grab(runtime) {
  for (let i = 0; i < 25; i += 1) {
    const snap = await runtime.draw()
    const s = snap?.session
    if (s?.rgba) return { rgba: Buffer.from(s.rgba), width: s.width, height: s.height }
    await runtime.tick(40)
  }
  throw new Error('no pixels')
}

async function tap(runtime, xy) {
  await runtime.touch({ x: xy[0], y: xy[1], gesture: 'tap' })
  await runtime.tick(360)
}

async function dismiss(runtime, n = 4) {
  for (let i = 0; i < n; i += 1) await tap(runtime, [TAP.overlay[0] + (i % 3) * 24, TAP.overlay[1]])
}

const files = loadProject(PROJECT)
const runtime = new XtappLuaRuntimeV2({
  model: 'x4_pro',
  orientation: 'portrait',
  locale: 'zh',
  files,
  storage: {},
  autoTick: false,
  workerFactory: createNodeWorker,
})
await runtime.start(files['index.lua'], 'index.lua')
for (let i = 0; i < 400 && !(await runtime.draw())?.session?.rgba; i += 1) {
  await new Promise((r) => setTimeout(r, 10))
}

rmSync(OUT, { recursive: true, force: true })
mkdirSync(OUT, { recursive: true })

const catalog = []
let seq = 0
async function shot(id, title) {
  seq += 1
  const name = `${String(seq).padStart(2, '0')}-${id}.png`
  const frame = await grab(runtime)
  const png = await encodeGrayPng(frame.rgba, frame.width, frame.height)
  writeFileSync(join(OUT, name), png)
  catalog.push({ n: seq, id, title, file: `maifangji/playtest/frames/${name}` })
}

await shot('story-1', '故事第1页')
await tap(runtime, TAP.storyContinue)
await shot('story-2', '故事第2页')
await tap(runtime, TAP.storyContinue)
await shot('story-3', '故事第3页')
await tap(runtime, TAP.storyContinue)
await shot('story-4', '故事第4页')
await tap(runtime, TAP.storyContinue)
await shot('story-5', '故事第5页 · 开始挑战')
await tap(runtime, TAP.storyStart)
await shot('main-empty', '主界面 · 未开局')

await tap(runtime, TAP.help)
await shot('help-1', '帮助第1步 · 目标')
for (let step = 2; step <= 9; step += 1) {
  await tap(runtime, TAP.helpNext)
  const titles = {
    2: '帮助第2步 · 货摊',
    3: '帮助第3步 · 货仓',
    4: '帮助第4步 · 状态栏',
    5: '帮助第5步 · 三个市场',
    6: '帮助第6步 · 银行',
    7: '帮助第7步 · 医院',
    8: '帮助第8步 · 售楼部',
    9: '帮助第9步 · 中介',
  }
  await shot(`help-${step}`, titles[step])
}
await tap(runtime, TAP.helpLeave)
await shot('main-after-help', '帮助离开后的空仓主界面')

await tap(runtime, TAP.startGame)
await shot('new-game', '开始游戏确认')
await tap(runtime, TAP.confirmNew)
await dismiss(runtime, 6)
await shot('playing', '对局主界面 · 第1周')

await tap(runtime, TAP.buy1)
await shot('buy-overlay', '买入弹层')
await tap(runtime, TAP.buyConfirm)
await tap(runtime, TAP.feedback)
await dismiss(runtime, 2)
await shot('after-buy', '买入后主界面')

await tap(runtime, TAP.sell1)
await shot('sell-overlay', '卖出弹层')
await tap(runtime, TAP.buyClose)

await tap(runtime, TAP.bank)
await shot('bank', '银行')
await tap(runtime, TAP.bankLeave)
await tap(runtime, TAP.hospital)
await shot('hospital', '医院')
await tap(runtime, TAP.hospitalLeave)
await tap(runtime, TAP.agency)
await shot('agency', '中介')
await tap(runtime, TAP.agencyLeave)
await tap(runtime, TAP.houses)
await shot('houses', '售楼部')
await tap(runtime, TAP.housesLeave)
await tap(runtime, TAP.records)
await shot('records', '历程表')
await tap(runtime, TAP.recordsLeave)

await tap(runtime, TAP.startGame)
await shot('quit-game', '结束游戏确认')
await tap(runtime, TAP.cancelQuit)

await tap(runtime, TAP.market2)
await dismiss(runtime, 6)
await shot('week-after-market2', '换农贸市场后（过周）')
await tap(runtime, TAP.market3)
await dismiss(runtime, 6)
await shot('week-after-market3', '换批发市场后（过周）')

const html = `<!doctype html>
<html lang="zh-CN">
<head>
<meta charset="utf-8">
<title>夜市置业 · 全部帧</title>
<style>
body { font: 16px/1.4 sans-serif; background: #ddd; margin: 0; padding: 16px; }
h1 { font-size: 20px; }
.grid { display: grid; grid-template-columns: repeat(auto-fill, minmax(240px, 1fr)); gap: 16px; }
figure { margin: 0; background: #fff; padding: 8px; }
img { width: 100%; height: auto; image-rendering: pixelated; background: #fff; border: 1px solid #000; }
figcaption { margin-top: 6px; font-size: 13px; }
</style>
</head>
<body>
<h1>夜市置业（买房记）全部帧 · ${catalog.length} 张</h1>
<p>当前代码截帧，480×800。点图可看原图。</p>
<div class="grid">
${catalog.map((item) => {
  const src = item.file.split('/').pop()
  return `<figure><a href="${src}" target="_blank"><img src="${src}" alt="${item.title}"></a><figcaption>${item.n}. ${item.title}<br><code>${src}</code></figcaption></figure>`
}).join('\n')}
</div>
</body>
</html>
`

writeFileSync(join(OUT, 'index.html'), html, 'utf8')
writeFileSync(join(OUT, 'catalog.json'), JSON.stringify({ count: catalog.length, frames: catalog }, null, 2) + '\n', 'utf8')
console.log(`frames=${catalog.length}`)
for (const item of catalog) console.log(`${item.n}\t${item.file}\t${item.title}`)
await Promise.race([runtime.dispose().catch(() => {}), new Promise((r) => setTimeout(r, 2000))])
