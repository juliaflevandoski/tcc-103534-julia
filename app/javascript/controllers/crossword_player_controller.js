import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["cell", "answer", "entry", "status"]

  connect() {
    this.cellsByPosition = new Map(this.cellTargets.map((cell) => [`${cell.dataset.row}-${cell.dataset.column}`, cell]))
  }

  inputLetter(event) {
    const input = event.currentTarget
    const normalized = [...input.value.normalize("NFD").replace(/\p{M}/gu, "").toUpperCase()]
      .find((character) => /^[A-Z]$/.test(character)) || ""
    input.value = normalized
    if (normalized) this.focusNext(input, 0, 1)
    this.updatePendingStatus()
  }

  navigateCells(event) {
    const offsets = {
      ArrowUp: [ -1, 0 ],
      ArrowDown: [ 1, 0 ],
      ArrowLeft: [ 0, -1 ],
      ArrowRight: [ 0, 1 ]
    }
    const offset = offsets[event.key]
    if (!offset) return
    event.preventDefault()
    this.focusNext(event.currentTarget, offset[0], offset[1])
  }

  focusNext(input, rowOffset, columnOffset) {
    let row = Number(input.dataset.row) + rowOffset
    let column = Number(input.dataset.column) + columnOffset
    const maxRow = Math.max(...this.cellTargets.map((cell) => Number(cell.dataset.row)))
    const maxColumn = Math.max(...this.cellTargets.map((cell) => Number(cell.dataset.column)))

    while (row >= 0 && row <= maxRow && column >= 0 && column <= maxColumn) {
      const nextCell = this.cellsByPosition.get(`${row}-${column}`)
      if (nextCell) {
        nextCell.focus()
        return
      }
      row += rowOffset
      column += columnOffset
    }
  }

  serializeAnswer(event) {
    const pendingEntries = this.pendingEntries()
    if (pendingEntries.length > 0) {
      event.preventDefault()
      this.updatePendingStatus()
      const entry = pendingEntries[0]
      const firstCell = this.cellTargets.find((cell) =>
        cell.dataset.row === entry.dataset.row && cell.dataset.column === entry.dataset.column
      )
      firstCell?.focus()
      return
    }

    const cells = Object.fromEntries(this.cellTargets.map((cell) => [
      `${cell.dataset.row}-${cell.dataset.column}`,
      cell.value.trim()
    ]))
    this.answerTarget.value = JSON.stringify({ cells })
  }

  updatePendingStatus() {
    const pendingEntries = this.pendingEntries()
    this.statusTarget.textContent = pendingEntries.length > 0 ?
      `Ainda faltam preencher ${pendingEntries.length} ${pendingEntries.length === 1 ? "palavra" : "palavras"}: ${pendingEntries.map((entry) => entry.dataset.pendingLabel).join(", ")}.` :
      "Todas as palavras estão preenchidas; respostas incorretas também podem ser enviadas."
  }

  pendingEntries() {
    return this.entryTargets.filter((entry) => {
      const rowOffset = entry.dataset.direction === "down" ? 1 : 0
      const columnOffset = entry.dataset.direction === "across" ? 1 : 0
      return Array.from({ length: Number(entry.dataset.length) }, (_, index) => {
        const row = Number(entry.dataset.row) + rowOffset * index
        const column = Number(entry.dataset.column) + columnOffset * index
        const cell = this.cellsByPosition.get(`${row}-${column}`)
        return !cell || cell.value.trim() === ""
      }).some(Boolean)
    })
  }
}