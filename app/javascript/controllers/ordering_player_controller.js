import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["list", "item", "status"]

  connect() {
    this.updateButtons()
  }

  moveUp(event) {
    event.preventDefault()
    const item = event.currentTarget.closest("[data-ordering-player-target='item']")
    if (!item.previousElementSibling) return

    this.listTarget.insertBefore(item, item.previousElementSibling)
    this.orderChanged()
  }

  moveDown(event) {
    event.preventDefault()
    const item = event.currentTarget.closest("[data-ordering-player-target='item']")
    if (!item.nextElementSibling) return

    this.listTarget.insertBefore(item.nextElementSibling, item)
    this.orderChanged()
  }

  startDrag(event) {
    if (event.target.closest?.("button")) {
      event.preventDefault()
      return
    }

    this.draggedItem = event.currentTarget
    event.dataTransfer.effectAllowed = "move"
    event.dataTransfer.setData("text/plain", this.draggedItem.dataset.itemId)
  }

  allowDrop(event) {
    event.preventDefault()
    event.dataTransfer.dropEffect = "move"
  }

  drop(event) {
    event.preventDefault()
    const target = event.currentTarget
    if (!this.draggedItem || target === this.draggedItem) return

    const items = this.itemTargets
    const draggedIndex = items.indexOf(this.draggedItem)
    const targetIndex = items.indexOf(target)
    this.listTarget.insertBefore(this.draggedItem, draggedIndex < targetIndex ? target.nextSibling : target)
    this.orderChanged()
  }

  endDrag() {
    this.draggedItem = null
  }

  announceOrder() {
    this.statusTarget.textContent = "Enviando a sequência escolhida."
  }

  orderChanged() {
    this.updateButtons()
    this.statusTarget.textContent = "Ordem atualizada."
  }

  updateButtons() {
    this.itemTargets.forEach((item, index) => {
      item.querySelector("[data-ordering-move-up]").disabled = index === 0
      item.querySelector("[data-ordering-move-down]").disabled = index === this.itemTargets.length - 1
    })
  }
}