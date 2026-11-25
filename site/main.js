// Theme switch: remembers the choice in this browser only.
document.getElementById('theme').addEventListener('click', () => {
  const root = document.documentElement
  const dark = root.dataset.theme
    ? root.dataset.theme === 'dark'
    : matchMedia('(prefers-color-scheme: dark)').matches
  root.dataset.theme = dark ? 'light' : 'dark'
  try { localStorage.setItem('theme', root.dataset.theme) } catch {}
})

// The demo: drag a box over the "video", or watch it play by itself.
const stage = document.getElementById('stage')
const screen = document.getElementById('screen')
const player = screen.querySelector('.player')
const box = document.getElementById('box')
const size = document.getElementById('size')
const hint = document.getElementById('hint')
const reduced = matchMedia('(prefers-reduced-motion: reduce)').matches
let start = null
let auto = null

function place(a, b) {
  const r = screen.getBoundingClientRect()
  const p = player.getBoundingClientRect()
  const clamp = (v, lo, hi) => Math.min(Math.max(v, lo), hi)
  const x1 = clamp(Math.min(a.x, b.x), p.left, p.right) - r.left
  const y1 = clamp(Math.min(a.y, b.y), p.top, p.bottom) - r.top
  const x2 = clamp(Math.max(a.x, b.x), p.left, p.right) - r.left
  const y2 = clamp(Math.max(a.y, b.y), p.top, p.bottom) - r.top
  Object.assign(box.style, { left: x1 + 'px', top: y1 + 'px', width: x2 - x1 + 'px', height: y2 - y1 + 'px' })
  size.textContent = `${Math.round(x2 - x1)} × ${Math.round(y2 - y1)}`
  box.hidden = false
  return { w: x2 - x1, h: y2 - y1 }
}

function finish() {
  stage.dataset.phase = 'done'
  hint.textContent = 'Copied. The panel can explain it, fix it or change it to Python.'
}

function reset() {
  clearTimeout(auto)
  box.hidden = true
  stage.dataset.phase = 'idle'
  hint.textContent = 'Drag over the code. It’s a video, so you can’t select it.'
}

function play() {
  reset()
  if (reduced) return finish()
  const code = screen.querySelector('code').getBoundingClientRect()
  const from = { x: code.left - 10, y: code.top - 10 }
  const to = { x: code.right + 10, y: code.bottom + 10 }
  const began = performance.now()
  stage.dataset.phase = 'dragging'
  function step(now) {
    if (stage.dataset.phase !== 'dragging' || start) return
    const t = Math.min(1, (now - began) / 900)
    const e = 1 - Math.pow(1 - t, 3)
    place(from, { x: from.x + (to.x - from.x) * e, y: from.y + (to.y - from.y) * e })
    if (t < 1) requestAnimationFrame(step)
    else auto = setTimeout(finish, 150)
  }
  requestAnimationFrame(step)
}

screen.addEventListener('pointerdown', (e) => {
  reset()
  start = { x: e.clientX, y: e.clientY }
  screen.setPointerCapture(e.pointerId)
  stage.dataset.phase = 'dragging'
})
screen.addEventListener('pointermove', (e) => {
  if (start) place(start, { x: e.clientX, y: e.clientY })
})
screen.addEventListener('pointerup', (e) => {
  if (!start) return
  const { w, h } = place(start, { x: e.clientX, y: e.clientY })
  start = null
  if (w > 20 && h > 12) finish()
  else reset()
})

document.getElementById('replay').addEventListener('click', play)

// Play once when the demo first comes into view.
new IntersectionObserver((entries, observer) => {
  if (entries.some((entry) => entry.isIntersecting)) {
    observer.disconnect()
    auto = setTimeout(play, 500)
  }
}, { threshold: 0.5 }).observe(stage)
