import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [
    "card", "status", "attempts", "matches", "errors", "score", "completion",
    "finalMatches", "finalHits", "finalAttempts", "finalErrors", "finalScore", "finalXp", "finalTime"
  ]

  static values = { turnUrl: String }

  connect() {
    this.selectedCardIds = this.cardTargets.filter((card) => card.dataset.selected === "true").map((card) => card.dataset.cardId)
    this.pendingResetIds = this.cardTargets.filter((card) => card.dataset.pendingReset === "true").map((card) => card.dataset.cardId)
    this.locked = this.pendingResetIds.length > 0
    if (this.locked) setTimeout(() => this.finishMismatch(), 900)
  }

  async selectCard(event) {
    const card = event.currentTarget
    const cardId = card.dataset.cardId
    if (this.locked || card.disabled || this.selectedCardIds.includes(cardId)) return

    this.locked = true
    try {
      const payload = await this.send("reveal", cardId)
      this.revealCard(card, payload.card)
      this.selectedCardIds.push(cardId)
      if (payload.comparison) {
        this.updateStats(payload)
        const firstCardId = this.selectedCardIds[0]
        const firstCard = this.cardTargets.find((candidate) => candidate.dataset.cardId === firstCardId)
        if (payload.matched) {
          this.markFound(firstCard)
          this.markFound(card)
          this.selectedCardIds = []
          this.locked = false
        } else {
          this.pendingResetIds = [ firstCardId, cardId ]
          firstCard.classList.add("is-mismatch")
          card.classList.add("is-mismatch")
          this.statusTarget.textContent = "Esse par não corresponde."
          setTimeout(() => this.finishMismatch(), 900)
        }
        if (payload.completed) this.finishGame(payload)
      } else {
        this.statusTarget.textContent = "Carta revelada. Escolha outra carta."
        this.locked = false
      }
    } catch (error) {
      this.statusTarget.textContent = error.message || "Não foi possível registrar essa jogada."
      this.locked = false
    }
  }

  async finishMismatch() {
    if (!this.pendingResetIds.length) return
    this.locked = true
    try {
      await this.send("reset")
      this.pendingResetIds.forEach((cardId) => {
        const card = this.cardTargets.find((candidate) => candidate.dataset.cardId === cardId)
        this.hideCard(card)
        card.classList.remove("is-mismatch")
      })
      this.pendingResetIds = []
      this.selectedCardIds = []
      this.statusTarget.textContent = "Escolha uma carta para começar."
    } catch (error) {
      this.statusTarget.textContent = error.message || "Não foi possível encerrar a comparação."
    }
    this.locked = false
  }

  async send(operation, cardId = null) {
    const response = await fetch(this.turnUrlValue, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "Accept": "application/json",
        "X-CSRF-Token": document.querySelector("meta[name='csrf-token']").content
      },
      body: JSON.stringify({ operation, card_id: cardId })
    })
    const payload = await response.json()
    if (!response.ok) throw new Error(payload.errors?.[0]?.message || "Jogada inválida.")
    return payload.data
  }

  revealCard(card, content) {
    card.replaceChildren()
    if (content.type === "word") {
      card.textContent = content.content
    } else {
      const image = document.createElement("img")
      image.src = content.url
      image.alt = "Imagem da carta"
      card.append(image)
    }
    card.classList.add("is-revealed")
    card.setAttribute("aria-label", content.type === "word" ? `Carta revelada: ${content.content}` : "Carta revelada: imagem")
    card.dataset.revealed = "true"
  }

  hideCard(card) {
    card.replaceChildren()
    const questionMark = document.createElement("span")
    questionMark.textContent = "?"
    questionMark.setAttribute("aria-hidden", "true")
    card.append(questionMark)
    card.classList.remove("is-revealed")
    card.setAttribute("aria-label", "Carta virada para baixo")
    card.dataset.revealed = "false"
  }

  markFound(card) {
    card.classList.add("is-found")
    card.classList.remove("is-mismatch")
    card.disabled = true
    card.dataset.found = "true"
    card.setAttribute("aria-label", "Par encontrado")
  }

  updateStats(payload) {
    this.attemptsTarget.textContent = payload.attempts
    this.matchesTarget.textContent = payload.matches
    this.errorsTarget.textContent = payload.errors
    this.scoreTarget.textContent = payload.score
  }

  finishGame(payload) {
    this.completionTarget.hidden = false
    this.finalMatchesTarget.textContent = payload.matches
    this.finalHitsTarget.textContent = payload.matches
    this.finalAttemptsTarget.textContent = payload.attempts
    this.finalErrorsTarget.textContent = payload.errors
    this.finalScoreTarget.textContent = payload.score
    this.finalXpTarget.textContent = payload.xp_awarded ? payload.score : 0
    this.finalTimeTarget.textContent = payload.time_spent
    this.statusTarget.textContent = payload.xp_awarded ? "Atividade concluída. XP atualizado." : "Atividade concluída."
    this.cardTargets.forEach((card) => { card.disabled = true })
  }
}