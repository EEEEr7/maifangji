// 对照 playtest 报告验收 UI-01..UI-05：帮助脚按钮、货列、弹层、售楼。
import { mkdirSync, readFileSync, readdirSync, statSync, writeFileSync } from 'node:fs'
import { dirname, join } from 'node:path'
import { fileURLToPath, pathToFileURL } from 'node:url'
import { Worker as NodeWorker } from 'node:worker_threads'

const HERE = dirname(fileURLToPath(import.meta.url))
const ROOT = join(HERE, '..', '..')
const PROJECT = join(ROOT, 'maifangji')
const OUT = join(HERE, 'verify')
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
  help: [79, 748],
  helpNext: [402, 770],
  helpLeave: [77, 770],
  bank: [59, 684],
  hospital: [179, 684],
  houses: [299, 684],
  buy1: [75, 182],
  buyClose: [356, 598],
  bankLeave: [356, 574],
  hospitalLeave: [302, 574],
  housesLeave: [380, 764],
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

function sampleRegion(rgba, x, y, w, h, width) {
  let black = 0
  let white = 0
  for (let row = y; row < y + h; row += 1) {
    for (let col = x; col < x + w; col += 1) {
      const v = rgba[(row * width + col) * 4]
      if (v < 40) black += 1
      else white += 1
    }
  }
  return { black, white }
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

mkdirSync(OUT, { recursive: true })
const shots = []
async function shot(name) {
  const frame = await grab(runtime)
  const png = await encodeGrayPng(frame.rgba, frame.width, frame.height)
  const file = join(OUT, `${name}.png`)
  writeFileSync(file, png)
  shots.push({ name, file, rgba: frame.rgba, width: frame.width })
}

for (let i = 0; i < 4; i += 1) await tap(runtime, TAP.storyContinue)
await tap(runtime, TAP.storyStart)
await shot('main-empty')
await tap(runtime, TAP.help)
await shot('help-1')
for (let i = 0; i < 4; i += 1) await tap(runtime, TAP.helpNext)
await shot('help-5')
for (let i = 0; i < 4; i += 1) await tap(runtime, TAP.helpNext)
await shot('help-9')
await tap(runtime, TAP.helpLeave)
await tap(runtime, TAP.startGame)
await shot('new-game')
await tap(runtime, TAP.confirmNew)
for (let i = 0; i < 6; i += 1) await tap(runtime, [240 + (i % 3) * 24, 400])
await shot('playing')
await tap(runtime, TAP.buy1)
await shot('buy-overlay')
await tap(runtime, TAP.buyClose)
await tap(runtime, TAP.bank)
await shot('bank')
await tap(runtime, TAP.bankLeave)
await tap(runtime, TAP.hospital)
await shot('hospital')
await tap(runtime, TAP.hospitalLeave)
await tap(runtime, TAP.houses)
await shot('houses')

const help1 = shots.find((s) => s.name === 'help-1')
const leave = sampleRegion(help1.rgba, 11, 740, 133, 60, help1.width)
const next = sampleRegion(help1.rgba, 336, 740, 133, 60, help1.width)
const empty = shots.find((s) => s.name === 'main-empty')
const healthDash = sampleRegion(empty.rgba, 367, 508, 80, 40, empty.width)
const goods = sampleRegion(empty.rgba, 10, 160, 140, 50, empty.width)
const playing = shots.find((s) => s.name === 'playing')
const buy = shots.find((s) => s.name === 'buy-overlay')
const footerWhileBuy = sampleRegion(buy.rgba, 13, 720, 133, 56, buy.width)
const buyTitle = sampleRegion(buy.rgba, 40, 416, 80, 28, buy.width)
const buyConfirm = sampleRegion(buy.rgba, 74, 572, 100, 52, buy.width)
const buyCancel = sampleRegion(buy.rgba, 306, 572, 100, 52, buy.width)
const buyName = sampleRegion(buy.rgba, 120, 456, 280, 32, buy.width)
const newGame = shots.find((s) => s.name === 'new-game')
const newConfirm = sampleRegion(newGame.rgba, 74, 548, 100, 52, newGame.width)
const newCancel = sampleRegion(newGame.rgba, 306, 548, 100, 52, newGame.width)
const houses = shots.find((s) => s.name === 'houses')
const houseName = sampleRegion(houses.rgba, 264, 96, 163, 32, houses.width)
const houseImage = sampleRegion(houses.rgba, 20, 110, 220, 170, houses.width)
const bank = shots.find((s) => s.name === 'bank')
const bankCopy = sampleRegion(bank.rgba, 50, 416, 360, 100, bank.width)
const hospital = shots.find((s) => s.name === 'hospital')
const hospitalCopy = sampleRegion(hospital.rgba, 50, 416, 360, 100, hospital.width)

const report = {
  leaveHasBothInk: leave.black > 80 && leave.white > 80,
  nextHasBothInk: next.black > 80 && next.white > 80,
  leave,
  next,
  goodsPanelMostlyWhite: goods.white > goods.black,
  goods,
  footerHiddenInBuy: footerWhileBuy.white > footerWhileBuy.black * 2,
  footerWhileBuy,
  houseNameHasContrast: houseName.black > 20 && houseName.white > 20,
  houseName,
  houseImageHasArt: houseImage.black > 800,
  houseImage,
  bankCopyVisible: bankCopy.black > 200,
  bankCopy,
  hospitalCopyVisible: hospitalCopy.black > 200,
  hospitalCopy,
  buyTitleVisible: buyTitle.black > 40,
  buyTitle,
  buyConfirmFilled: buyConfirm.black > 1200,
  buyConfirm,
  buyCancelOutlined: buyCancel.black > 80 && buyCancel.white > 80,
  buyCancel,
  buyNameVisible: buyName.black > 80,
  buyName,
  newConfirmFilled: newConfirm.black > 1200,
  newConfirm,
  newCancelOutlined: newCancel.black > 80 && newCancel.white > 80,
  newCancel,
  files: shots.map((s) => s.file),
}
writeFileSync(join(OUT, 'checks.json'), JSON.stringify(report, null, 2), 'utf8')
console.log(JSON.stringify(report, null, 2))
await Promise.race([runtime.dispose().catch(() => {}), new Promise((r) => setTimeout(r, 2000))])
const ok = report.leaveHasBothInk && report.nextHasBothInk && report.goodsPanelMostlyWhite
  && report.footerHiddenInBuy && report.houseImageHasArt && report.bankCopyVisible
  && report.hospitalCopyVisible && report.buyTitleVisible && report.buyConfirmFilled
  && report.buyCancelOutlined && report.buyNameVisible && report.newConfirmFilled
  && report.newCancelOutlined
process.exit(ok ? 0 : 1)
