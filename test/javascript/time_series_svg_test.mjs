import assert from "node:assert/strict"
import test from "node:test"
import { buildSvg } from "../../app/javascript/charts/time_series_svg.js"

const PLOT_LEFT = 44
const PLOT_RIGHT = 624
const PLOT_TOP = 16
const PLOT_HEIGHT = 228

function chartFor(values, type = "line") {
  return {
    type,
    unit: type === "bar" ? "count" : "percent",
    title: "Weekly chart",
    description: "Weekly values",
    weeks: values.map((_, index) => ({ label: `W${index + 1}`, full: `Week ${index + 1}` })),
    series: [ { label: "Series", values } ]
  }
}

function emptyRects(svg) {
  return [ ...svg.matchAll(/<rect class="time-series-chart-empty" x="([\d.]+)" y="([\d.]+)" width="([\d.]+)" height="([\d.]+)"/g) ]
    .map(([, x, y, width, height]) => ({ x: Number(x), y: Number(y), width: Number(width), height: Number(height) }))
}

function assertWithinPlot(rect) {
  assert.ok(rect.x >= PLOT_LEFT)
  assert.ok(rect.x + rect.width <= PLOT_RIGHT)
  assert.equal(rect.y, PLOT_TOP)
  assert.equal(rect.height, PLOT_HEIGHT)
}

function markerYs(svg) {
  return [ ...svg.matchAll(/<circle class="time-series-chart-marker [^"]*" cx="[\d.]+" cy="([\d.]+)"/g) ].map(([, cy]) => Number(cy))
}

function bars(svg) {
  return [ ...svg.matchAll(/<rect class="time-series-chart-bar [^"]*" x="([\d.]+)" y="([\d.]+)" width="([\d.]+)" height="([\d.]+)"/g) ]
    .map(([, x, y, width, height]) => ({ x: Number(x), y: Number(y), width: Number(width), height: Number(height) }))
}

function polylineCount(svg) {
  return [ ...svg.matchAll(/<polyline /g) ].length
}

const ZERO_Y = PLOT_TOP + PLOT_HEIGHT

test("bounds an empty initial line-chart week at the plot edge and next midpoint", () => {
  const [ rect ] = emptyRects(buildSvg(chartFor([ null, 50, 60 ])))

  assert.deepEqual(rect, { x: 44, y: 16, width: 145, height: 228 })
  assertWithinPlot(rect)
})

test("bounds an empty final line-chart week at the previous midpoint and plot edge", () => {
  const [ rect ] = emptyRects(buildSvg(chartFor([ 60, 50, null ])))

  assert.deepEqual(rect, { x: 479, y: 16, width: 145, height: 228 })
  assertWithinPlot(rect)
})

test("uses neighboring midpoints for an empty intermediate line-chart week", () => {
  const [ rect ] = emptyRects(buildSvg(chartFor([ 60, null, 80 ])))

  assert.deepEqual(rect, { x: 189, y: 16, width: 290, height: 228 })
  assertWithinPlot(rect)
})

test("uses the full plot width for a single empty line-chart week", () => {
  const [ rect ] = emptyRects(buildSvg(chartFor([ null ])))

  assert.deepEqual(rect, { x: 44, y: 16, width: 580, height: 228 })
  assertWithinPlot(rect)
})

test("keeps each of two empty-week bands within its half of the line chart", () => {
  const initial = emptyRects(buildSvg(chartFor([ null, 50 ])))[0]
  const final = emptyRects(buildSvg(chartFor([ 50, null ])))[0]

  assert.deepEqual(initial, { x: 44, y: 16, width: 290, height: 228 })
  assert.deepEqual(final, { x: 334, y: 16, width: 290, height: 228 })
  assertWithinPlot(initial)
  assertWithinPlot(final)
})

test("keeps empty-week bands within the plot in a longer line chart", () => {
  const rects = emptyRects(buildSvg(chartFor([ null, 20, 30, 40, null, 60, 70, 80, null ])))

  assert.deepEqual(rects, [
    { x: 44, y: 16, width: 36.3, height: 228 },
    { x: 297.8, y: 16, width: 72.5, height: 228 },
    { x: 587.8, y: 16, width: 36.2, height: 228 }
  ])
  rects.forEach(assertWithinPlot)
})

test("preserves equal slot geometry for empty weeks in bar charts", () => {
  const [ rect ] = emptyRects(buildSvg(chartFor([ 3, null, 1 ], "bar")))

  assert.deepEqual(rect, { x: 237.3, y: 16, width: 193.3, height: 228 })
  assertWithinPlot(rect)
})

test("line chart draws a no-data band and no marker for a null week", () => {
  const svg = buildSvg(chartFor([ 60, null, 80 ]))

  assert.equal(emptyRects(svg).length, 1)
  assert.equal(markerYs(svg).length, 2)
  assert.match(svg, /Week 2: sem dados/)
  assert.doesNotMatch(svg, /Week 2: \d/)
})

test("line chart treats zero as a valid point on the baseline, not as missing data", () => {
  const svg = buildSvg(chartFor([ 0, 0, 0 ]))

  assert.equal(emptyRects(svg).length, 0)
  assert.deepEqual(markerYs(svg), [ ZERO_Y, ZERO_Y, ZERO_Y ])
  assert.equal(polylineCount(svg), 1)
  assert.match(svg, /Series, Week 1: 0\.0%/)
  assert.doesNotMatch(svg, /sem dados/)
})

test("a single zero week is a point, while a single null week is only a no-data band", () => {
  const zero = buildSvg(chartFor([ 0 ]))
  const missing = buildSvg(chartFor([ null ]))

  assert.deepEqual(markerYs(zero), [ ZERO_Y ])
  assert.equal(emptyRects(zero).length, 0)
  assert.equal(markerYs(missing).length, 0)
  assert.equal(emptyRects(missing).length, 1)
})

test("bar chart draws a zero-height bar for zero and no no-data band", () => {
  const svg = buildSvg(chartFor([ 3, 0, 1 ], "bar"))
  const drawn = bars(svg)

  assert.equal(emptyRects(svg).length, 0)
  assert.equal(drawn.length, 3)
  assert.equal(drawn[1].height, 0)
  assert.equal(drawn[1].y, ZERO_Y)
  assert.ok(drawn[0].height > 0 && drawn[2].height > 0)
  assert.match(svg, /Series, Week 2: 0</)
})

test("bar chart separates null weeks (band, no bar) from zero weeks (bar, no band)", () => {
  const svg = buildSvg(chartFor([ null, 0, 2 ], "bar"))
  const rects = emptyRects(svg)

  assert.equal(rects.length, 1)
  assert.equal(bars(svg).length, 2)
  assert.ok(rects[0].x < bars(svg)[0].x)
  rects.forEach(assertWithinPlot)
})

test("a mixed null, zero and positive line sequence keeps each week's meaning", () => {
  const svg = buildSvg(chartFor([ null, 0, 50, null, 100, 0, null ]))
  const rects = emptyRects(svg)

  assert.deepEqual(markerYs(svg), [ ZERO_Y, 130, 16, ZERO_Y ])
  assert.equal(polylineCount(svg), 2)
  assert.deepEqual(rects.map(({ x, width }) => ({ x, width })), [
    { x: 44, width: 48.3 },
    { x: 285.7, width: 96.6 },
    { x: 575.7, width: 48.3 }
  ])
  rects.forEach(assertWithinPlot)
  assert.equal((svg.match(/: sem dados/g) || []).length, 3)
})

test("no-data bands stay inside the plot for null at every position and for mixed bar charts", () => {
  const lineSequences = [ [ null, 0 ], [ 0, null ], [ null, null, null ], [ 0, null, 0 ], [ null, 0, 0, 0, null ] ]
  const rects = [
    ...lineSequences.flatMap((values) => emptyRects(buildSvg(chartFor(values)))),
    ...emptyRects(buildSvg(chartFor([ null, 0, null, 4 ], "bar")))
  ]

  assert.ok(rects.length > 0)
  rects.forEach(assertWithinPlot)
})