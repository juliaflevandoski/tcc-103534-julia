import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["list"]
  static values = { url: String }

  connect() {
    this.draggedRow = null
    this.listTarget.addEventListener("dragstart", this.startDrag)
    this.listTarget.addEventListener("dragover", this.allowDrop)
    this.listTarget.addEventListener("drop", this.drop)
  }

  disconnect() {
    this.listTarget.removeEventListener("dragstart", this.startDrag)
    this.listTarget.removeEventListener("dragover", this.allowDrop)
    this.listTarget.removeEventListener("drop", this.drop)
  }

  startDrag = (event) => {
    this.draggedRow = event.target.closest("tr[data-id]")
    event.dataTransfer.effectAllowed = "move"
  }

  allowDrop = (event) => {
    event.preventDefault()
  }

  drop = (event) => {
    event.preventDefault()
    const targetRow = event.target.closest("tr[data-id]")
    if (!this.draggedRow || !targetRow || this.draggedRow === targetRow) return

    const rows = [...this.listTarget.querySelectorAll("tr[data-id]")]
    const draggedIndex = rows.indexOf(this.draggedRow)
    const targetIndex = rows.indexOf(targetRow)
    targetRow.parentNode.insertBefore(this.draggedRow, draggedIndex < targetIndex ? targetRow.nextSibling : targetRow)
    this.persistOrder()
  }

  persistOrder() {
    const orderedIds = [...this.listTarget.querySelectorAll("tr[data-id]")].map((row) => row.dataset.id)
    fetch(this.urlValue, {
      method: "PATCH",
      headers: {
        "Content-Type": "application/json",
        "Accept": "application/json",
        "X-CSRF-Token": document.querySelector("meta[name='csrf-token']").content
      },
      body: JSON.stringify({ ordered_ids: orderedIds })
    }).then((response) => {
      if (!response.ok) window.location.reload()
      else this.updateDisplayedPositions()
    })
  }

  updateDisplayedPositions() {
    this.listTarget.querySelectorAll("tr[data-id]").forEach((row, index) => {
      row.querySelector("[data-position]").textContent = index + 1
    })
  }
}