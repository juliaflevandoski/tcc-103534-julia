// Gera o SVG de um gráfico temporal a partir do contrato de dados do Rails (ver TimeSeriesChartHelper).
// Não calcula notas nem médias: apenas posiciona os valores recebidos. Valores null são lacunas.

const WIDTH = 640
const HEIGHT = 280
const MARGIN = { top: 16, right: 16, bottom: 36, left: 44 }
const SVG_NS = "http://www.w3.org/2000/svg"
const MAX_VALUE_LABELS = 12
const MAX_X_LABELS = 8

export function niceCountTicks(maxValue) {
  const max = Math.max(Math.ceil(maxValue), 1)
  const step = Math.max(Math.ceil(max / 4), 1)
  const top = Math.ceil(max / step) * step
  const ticks = []
  for (let value = 0; value <= top; value += step) ticks.push(value)
  return ticks
}

export function scaleFor(chart) {
  if (chart.unit === "percent") return { ticks: [ 0, 25, 50, 75, 100 ], max: 100 }

  const values = chart.series.flatMap((series) => series.values).filter((value) => value !== null)
  const ticks = niceCountTicks(Math.max(0, ...values))
  return { ticks, max: ticks[ticks.length - 1] }
}

export function formatValue(value, unit) {
  return unit === "percent" ? `${Number(value).toFixed(1)}%` : String(value)
}

function tickLabel(value, unit) {
  return unit === "percent" ? `${value}%` : String(value)
}

function escapeText(text) {
  return String(text).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;")
}

function marker(shape, x, y, className, label) {
  const title = `<title>${escapeText(label)}</title>`
  if (shape === 1) return `<rect class="${className}" x="${(x - 4).toFixed(1)}" y="${(y - 4).toFixed(1)}" width="8" height="8">${title}</rect>`
  return `<circle class="${className}" cx="${x.toFixed(1)}" cy="${y.toFixed(1)}" r="4.5">${title}</circle>`
}

export function buildSvg(chart, ids = { title: "chart-title", description: "chart-description" }) {
  const plotWidth = WIDTH - MARGIN.left - MARGIN.right
  const plotHeight = HEIGHT - MARGIN.top - MARGIN.bottom
  const count = chart.weeks.length
  const { ticks, max } = scaleFor(chart)
  const bar = chart.type === "bar"
  const slot = plotWidth / count
  const xFor = (index) => MARGIN.left + (bar || count === 1 ? slot * (index + 0.5) : (plotWidth * index) / (count - 1))
  const yFor = (value) => MARGIN.top + plotHeight - (value / max) * plotHeight
  const showValues = count <= MAX_VALUE_LABELS
  const xStep = Math.ceil(count / MAX_X_LABELS)
  const parts = []

  parts.push(`<svg class="time-series-chart-svg" viewBox="0 0 ${WIDTH} ${HEIGHT}" role="img" aria-labelledby="${ids.title} ${ids.description}" focusable="false" xmlns="${SVG_NS}">`)
  parts.push(`<title id="${ids.title}">${escapeText(chart.title)}</title><desc id="${ids.description}">${escapeText(chart.description)}</desc>`)

  chart.weeks.forEach((week, index) => {
    if (chart.series.every((series) => series.values[index] === null)) {
      parts.push(`<rect class="time-series-chart-empty" x="${(xFor(index) - slot / 2).toFixed(1)}" y="${MARGIN.top}" width="${slot.toFixed(1)}" height="${plotHeight}"><title>${escapeText(`${week.full}: sem dados`)}</title></rect>`)
    }
  })

  ticks.forEach((tick) => {
    const y = yFor(tick).toFixed(1)
    parts.push(`<line class="time-series-chart-grid" x1="${MARGIN.left}" x2="${WIDTH - MARGIN.right}" y1="${y}" y2="${y}"/>`)
    parts.push(`<text class="time-series-chart-tick" x="${MARGIN.left - 8}" y="${y}" text-anchor="end" dominant-baseline="middle">${tickLabel(tick, chart.unit)}</text>`)
  })
  parts.push(`<line class="time-series-chart-axis" x1="${MARGIN.left}" x2="${WIDTH - MARGIN.right}" y1="${yFor(0)}" y2="${yFor(0)}"/>`)

  chart.weeks.forEach((week, index) => {
    if (index % xStep !== 0) return
    parts.push(`<text class="time-series-chart-tick" x="${xFor(index).toFixed(1)}" y="${HEIGHT - MARGIN.bottom + 18}" text-anchor="middle">${escapeText(week.label)}</text>`)
  })

  const groupWidth = Math.min(slot * 0.7, 48)
  const barWidth = groupWidth / chart.series.length

  chart.series.forEach((series, seriesIndex) => {
    const cls = `time-series-chart-series--${seriesIndex % 3}`
    const labelFor = (index, value) => `${series.label}, ${chart.weeks[index].full}: ${formatValue(value, chart.unit)}`

    if (bar) {
      series.values.forEach((value, index) => {
        if (value === null) return
        const x = xFor(index) - groupWidth / 2 + barWidth * seriesIndex
        const y = yFor(value)
        const height = Math.max(yFor(0) - y, value > 0 ? 1 : 0)
        parts.push(`<rect class="time-series-chart-bar ${cls}" x="${x.toFixed(1)}" y="${y.toFixed(1)}" width="${Math.max(barWidth - 2, 2).toFixed(1)}" height="${height.toFixed(1)}" rx="2"><title>${escapeText(labelFor(index, value))}</title></rect>`)
        if (showValues) parts.push(`<text class="time-series-chart-value" x="${(x + barWidth / 2).toFixed(1)}" y="${(y - 5).toFixed(1)}" text-anchor="middle">${formatValue(value, chart.unit)}</text>`)
      })
      return
    }

    let segment = []
    const flush = () => {
      if (segment.length > 1) parts.push(`<polyline class="time-series-chart-line ${cls}" points="${segment.join(" ")}" fill="none"/>`)
      segment = []
    }
    series.values.forEach((value, index) => {
      if (value === null) return flush()
      segment.push(`${xFor(index).toFixed(1)},${yFor(value).toFixed(1)}`)
    })
    flush()
    series.values.forEach((value, index) => {
      if (value === null) return
      parts.push(marker(seriesIndex % 2, xFor(index), yFor(value), `time-series-chart-marker ${cls}`, labelFor(index, value)))
      if (showValues) parts.push(`<text class="time-series-chart-value" x="${xFor(index).toFixed(1)}" y="${(yFor(value) - 10).toFixed(1)}" text-anchor="middle">${formatValue(value, chart.unit)}</text>`)
    })
  })

  parts.push("</svg>")
  return parts.join("")
}

export function legendItems(chart) {
  return chart.series.map((series, index) => ({ label: series.label, className: `time-series-chart-series--${index % 3}`, shape: index % 2 }))
}
