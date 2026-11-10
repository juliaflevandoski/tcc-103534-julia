import { Controller } from "@hotwired/stimulus"
import { buildSvg, legendItems } from "charts/time_series_svg"

// Renderiza um gráfico temporal em SVG a partir do JSON fornecido pelo Rails.
// Sem JavaScript, a tabela de valores (aberta por padrão) continua disponível.
export default class extends Controller {
  static targets = [ "canvas", "legend", "table" ]
  static values = { chart: Object }

  connect() {
    const chart = this.chartValue
    if (!chart || !Array.isArray(chart.weeks) || chart.weeks.length === 0) return

    const uid = this.element.id || `time-series-chart-${Math.random().toString(36).slice(2, 8)}`
    this.canvasTarget.innerHTML = buildSvg(chart, { title: `${uid}-title`, description: `${uid}-description` })
    this.renderLegend(chart)
    if (this.hasTableTarget) this.tableTarget.open = false
    this.observeScroll(chart)
  }

  disconnect() {
    this.resizeObserver?.disconnect()
  }

  // A área só rola em telas estreitas; fora disso não vira região nem parada de teclado.
  observeScroll(chart) {
    const canvas = this.canvasTarget
    const update = () => this.markScrollable(canvas.scrollWidth > canvas.clientWidth + 1, chart)
    this.resizeObserver = new ResizeObserver(update)
    this.resizeObserver.observe(canvas)
    update()
  }

  markScrollable(scrolls, chart) {
    const canvas = this.canvasTarget
    if (scrolls) {
      canvas.setAttribute("role", "region")
      canvas.setAttribute("aria-label", `${chart.title} (rolagem horizontal)`)
      canvas.tabIndex = 0
    } else {
      canvas.removeAttribute("role")
      canvas.removeAttribute("aria-label")
      canvas.removeAttribute("tabindex")
    }
  }

  renderLegend(chart) {
    if (!this.hasLegendTarget || chart.series.length < 2) return

    this.legendTarget.replaceChildren(...legendItems(chart).map((item) => {
      const entry = document.createElement("li")
      entry.className = `time-series-chart-legend-item ${item.className}`
      const swatch = document.createElement("span")
      swatch.className = `time-series-chart-swatch time-series-chart-swatch--${item.shape}`
      swatch.setAttribute("aria-hidden", "true")
      entry.append(swatch, item.label)
      return entry
    }))
  }
}
