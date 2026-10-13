import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["field", "status"]

  connect() {
    this.update()
  }

  update() {
    const pending = this.pendingGroups()
    if (pending.length === 0) {
      this.statusTarget.textContent = "Todas as respostas obrigatórias foram preenchidas."
      return
    }

    this.statusTarget.textContent = `Ainda falta responder: ${pending.map((group) => group.label).join(", ")}.`
  }

  validate(event) {
    const pending = this.pendingGroups()
    this.update()
    if (pending.length === 0) return

    event.preventDefault()
    pending[0].fields[0].focus()
  }

  pendingGroups() {
    const groups = new Map()
    this.fieldTargets.forEach((field) => {
      const group = field.dataset.responseGroup
      groups.set(group, [ ...(groups.get(group) || []), field ])
    })

    return Array.from(groups.values()).filter((fields) => {
      if (fields[0].type === "radio") return !fields.some((field) => field.checked)

      return fields.some((field) => field.value.trim() === "")
    }).map((fields) => ({ label: fields[0].dataset.responseLabel, fields }))
  }
}