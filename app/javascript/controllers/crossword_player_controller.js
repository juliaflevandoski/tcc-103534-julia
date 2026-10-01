import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["cell", "answer"]

  connect() {
    this.cellsByPosition = new Map(this.cellTargets.map((cell) => [`${cell.dataset.row}-${cell.dataset.column}`, cell]))
  }

  inputLetter(event) {
    const input = event.currentTarget
    const normalized = [...input.value.normalize("NFD").replace(/\p{M}/gu, "").toUpperCase()]
      .find((character) => /^[A-Z]$/.test(character)) || ""
    input.value = normalized
    if (normalized) this.focusNext(input, 0, 1)
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
    const cells = Object.fromEntries(this.cellTargets.map((cell) => [
      `${cell.dataset.row}-${cell.dataset.column}`,
      cell.value.trim()
    ]))
    this.answerTarget.value = JSON.stringify({ cells })
  }
}