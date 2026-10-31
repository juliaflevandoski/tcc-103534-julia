import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["sentence", "status", "answerInput", "submitButton"]

  connect() {
    this.sentenceTargets.forEach((sentence) => this.updateButtons(this.listFor(sentence)))
    this.updateAnswer()
  }

  submit(event) {
    if (this.submitting) {
      event.preventDefault()
      return
    }

    this.updateAnswer()
    if (!this.complete) {
      event.preventDefault()
      this.statusTarget.textContent = "A resposta está incompleta. Confira todas as palavras de cada frase."
      return
    }

    this.submitting = true
    this.submitButtonTarget.disabled = true
    this.statusTarget.textContent = "Enviando as frases organizadas."
  }

  moveUp(event) {
    event.preventDefault()
    if (this.submitting) return
    const item = event.currentTarget.closest("[data-ordering-multiple-player-target='item']")
    const list = item.closest("[data-ordering-multiple-player-list]")
    if (!item.previousElementSibling) return

    list.insertBefore(item, item.previousElementSibling)
    this.orderChanged(item.closest("[data-ordering-multiple-player-target='sentence']"), list)
  }

  moveDown(event) {
    event.preventDefault()
    if (this.submitting) return
    const item = event.currentTarget.closest("[data-ordering-multiple-player-target='item']")
    const list = item.closest("[data-ordering-multiple-player-list]")
    if (!item.nextElementSibling) return

    list.insertBefore(item.nextElementSibling, item)
    this.orderChanged(item.closest("[data-ordering-multiple-player-target='sentence']"), list)
  }

  startDrag(event) {
    if (this.submitting) {
      event.preventDefault()
      return
    }
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
    if (this.submitting) return
    const target = event.currentTarget
    if (!this.draggedItem || target === this.draggedItem) return

    const sourceList = this.draggedItem.closest("[data-ordering-multiple-player-list]")
    const targetList = target.closest("[data-ordering-multiple-player-list]")
    if (sourceList !== targetList) return

    const items = [...targetList.querySelectorAll("[data-ordering-multiple-player-target='item']")]
    const draggedIndex = items.indexOf(this.draggedItem)
    const targetIndex = items.indexOf(target)
    targetList.insertBefore(this.draggedItem, draggedIndex < targetIndex ? target.nextSibling : target)
    this.orderChanged(target.closest("[data-ordering-multiple-player-target='sentence']"), targetList)
  }

  endDrag() {
    this.draggedItem = null
  }

  listFor(sentence) {
    return sentence.querySelector("[data-ordering-multiple-player-list]")
  }

  orderChanged(sentence, list) {
    this.updateButtons(list)
    this.updateAnswer()
    const sentenceNumber = this.sentenceTargets.indexOf(sentence) + 1
    this.statusTarget.textContent = `Ordem da frase ${sentenceNumber} atualizada. Você pode continuar reorganizando antes de enviar.`
  }

  updateButtons(list) {
    const items = [...list.querySelectorAll("[data-ordering-multiple-player-target='item']")]
    items.forEach((item, index) => {
      const buttons = item.querySelectorAll(".ordering-player-actions button")
      buttons[0].disabled = index === 0
      buttons[1].disabled = index === items.length - 1
    })
  }

  updateAnswer() {
    this.answer = {
      sentences: this.sentenceTargets.map((sentence) => ({
        id: sentence.dataset.sentenceId,
        ordered_ids: [...this.listFor(sentence).querySelectorAll("[data-ordering-multiple-player-target='item']")]
          .map((item) => item.dataset.itemId)
      }))
    }
    this.complete = this.sentenceTargets.length === this.answer.sentences.length &&
      this.sentenceTargets.every((sentence, index) => {
        const expectedIds = JSON.parse(sentence.dataset.expectedIds || "[]")
        const orderedIds = this.answer.sentences[index].ordered_ids
        return expectedIds.length > 0 && orderedIds.length === expectedIds.length &&
          new Set(orderedIds).size === orderedIds.length &&
          expectedIds.every((id) => orderedIds.includes(id))
      })
    this.answerInputTarget.value = JSON.stringify(this.answer.sentences)
    this.submitButtonTarget.disabled = !this.complete || this.submitting
    if (!this.submitting) {
      this.statusTarget.textContent = this.complete ?
        "Todas as frases estão completas e podem ser enviadas." :
        "A resposta está incompleta. Confira todas as palavras de cada frase."
    }
  }
}