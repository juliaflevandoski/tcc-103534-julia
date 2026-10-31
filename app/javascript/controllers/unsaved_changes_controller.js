import { Controller } from "@hotwired/stimulus"

// Avisa ao sair do formulário com alterações não salvas. Compara um retrato
// dos campos do editor com o estado inicial; campos dentro de <dialog>
// (modais de IA) são ignorados até que o conteúdo seja aplicado ao editor.
export default class extends Controller {
  static values = {
    startDirty: { type: Boolean, default: false },
    message: { type: String, default: "Você tem alterações não salvas. Deseja sair mesmo assim?" }
  }

  connect() {
    this.submitting = false
    this.baseline = this.snapshot()
    this.beforeUnload = (event) => {
      if (!this.dirty()) return
      event.preventDefault()
      event.returnValue = ""
    }
    this.beforeVisit = (event) => {
      if (!this.dirty()) return
      if (!window.confirm(this.messageValue)) event.preventDefault()
    }
    window.addEventListener("beforeunload", this.beforeUnload)
    document.addEventListener("turbo:before-visit", this.beforeVisit)
  }

  disconnect() {
    window.removeEventListener("beforeunload", this.beforeUnload)
    document.removeEventListener("turbo:before-visit", this.beforeVisit)
  }

  // Disparado pelo Turbo somente quando o envio realmente começa (não se a validação local o cancelar).
  submitStart() {
    this.submitting = true
  }

  submitEnd(event) {
    if (!event.detail.success) this.submitting = false
  }

  dirty() {
    if (this.submitting) return false
    return this.startDirtyValue || this.snapshot() !== this.baseline
  }

  snapshot() {
    return [...this.element.querySelectorAll("input, textarea, select")]
      .filter((field) => !field.closest("dialog") && field.type !== "hidden")
      .map((field) => {
        if (field.type === "checkbox" || field.type === "radio") return `${field.type}:${field.checked}`
        if (field.type === "file") return `file:${[...field.files].map((file) => `${file.name}:${file.size}`).join(",")}`
        return `${field.tagName}:${field.value}`
      })
      .join("\u0001")
  }
}
