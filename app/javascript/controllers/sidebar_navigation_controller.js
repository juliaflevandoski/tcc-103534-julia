import { Controller } from "@hotwired/stimulus"

const MOBILE_QUERY = "(max-width: 48rem)"

export default class extends Controller {
  static targets = ["sidebar", "backdrop", "toggle"]

  connect() {
    this.mobilePreference = window.matchMedia(MOBILE_QUERY)
    this.focusFrameId = null
    this.handleMediaChange = this.mediaChanged.bind(this)
    this.handleKeydown = this.keydown.bind(this)
    this.mobilePreference.addEventListener("change", this.handleMediaChange)
    document.addEventListener("keydown", this.handleKeydown)
    this.close({ restoreFocus: false })
  }

  disconnect() {
    if (this.focusFrameId !== null) cancelAnimationFrame(this.focusFrameId)
    this.mobilePreference?.removeEventListener("change", this.handleMediaChange)
    document.removeEventListener("keydown", this.handleKeydown)
  }

  toggle() {
    if (!this.mobilePreference.matches) return

    if (this.isOpen) {
      this.close()
    } else {
      this.open()
    }
  }

  open() {
    if (!this.mobilePreference.matches) return

    this.sidebarTarget.classList.add("is-open")
    this.sidebarTarget.inert = false
    this.backdropTarget.hidden = false
    this.toggleTarget.setAttribute("aria-expanded", "true")
    this.toggleTarget.setAttribute("aria-label", "Fechar menu de navegação")
    const firstLink = this.sidebarTarget.querySelector(".internal-navigation-link")
    if (firstLink) {
      this.focusFrameId = requestAnimationFrame(() => {
        this.focusFrameId = null
        if (this.isOpen) firstLink.focus()
      })
    }
  }

  close({ restoreFocus = true } = {}) {
    const wasOpen = this.isOpen
    if (this.focusFrameId !== null) cancelAnimationFrame(this.focusFrameId)
    this.focusFrameId = null
    this.sidebarTarget.classList.remove("is-open")
    this.sidebarTarget.inert = this.mobilePreference.matches
    this.backdropTarget.hidden = true
    this.toggleTarget.setAttribute("aria-expanded", "false")
    this.toggleTarget.setAttribute("aria-label", "Abrir menu de navegação")

    if (restoreFocus && wasOpen && this.mobilePreference.matches) this.toggleTarget.focus()
  }

  closeAfterNavigate() {
    this.close({ restoreFocus: false })
  }

  keydown(event) {
    if (!this.isOpen) return

    if (event.key === "Escape") {
      this.close()
      return
    }

    if (event.key !== "Tab") return

    const focusableElements = this.sidebarTarget.querySelectorAll("a[href], button:not([disabled])")
    const firstElement = focusableElements[0]
    const lastElement = focusableElements[focusableElements.length - 1]

    if (event.shiftKey && document.activeElement === firstElement) {
      event.preventDefault()
      lastElement.focus()
    } else if (!event.shiftKey && (document.activeElement === lastElement || !this.sidebarTarget.contains(document.activeElement))) {
      event.preventDefault()
      firstElement.focus()
    }
  }

  mediaChanged() {
    this.close({ restoreFocus: false })
  }

  get isOpen() {
    return this.sidebarTarget.classList.contains("is-open")
  }
}
