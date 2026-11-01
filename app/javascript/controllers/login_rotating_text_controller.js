import { Controller } from "@hotwired/stimulus"

const REDUCED_MOTION_QUERY = "(prefers-reduced-motion: reduce)"
const ROTATION_INTERVAL = 3000

export default class extends Controller {
  static targets = ["word"]

  connect() {
    this.motionPreference = window.matchMedia(REDUCED_MOTION_QUERY)
    this.currentIndex = 0
    this.nextIndex = null
    this.isTransitioning = false
    this.frameId = null
    this.intervalId = null
    this.handleMotionPreferenceChange = this.motionPreferenceChanged.bind(this)
    this.handleTransitionEnd = this.transitionEnded.bind(this)

    this.element.addEventListener("transitionend", this.handleTransitionEnd)
    this.motionPreference.addEventListener("change", this.handleMotionPreferenceChange)
    this.showStaticWord()
    if (!this.motionPreference.matches) this.startRotation()
  }

  disconnect() {
    this.stopRotation()
    if (this.frameId !== null) cancelAnimationFrame(this.frameId)
    this.frameId = null
    this.isTransitioning = false
    this.nextIndex = null
    this.motionPreference?.removeEventListener("change", this.handleMotionPreferenceChange)
    this.element.removeEventListener("transitionend", this.handleTransitionEnd)
  }

  startRotation() {
    if (this.intervalId !== null || this.wordTargets.length < 2) return

    this.intervalId = window.setInterval(() => this.rotate(), ROTATION_INTERVAL)
  }

  stopRotation() {
    if (this.intervalId !== null) window.clearInterval(this.intervalId)
    this.intervalId = null
  }

  rotate() {
    if (this.isTransitioning) return

    const previousWord = this.wordTargets[this.currentIndex]
    this.nextIndex = (this.currentIndex + 1) % this.wordTargets.length
    this.isTransitioning = true
    previousWord.classList.remove("is-active")
    previousWord.classList.add("is-exiting")
  }

  transitionEnded(event) {
    if (event.propertyName !== "transform" || !event.target.classList.contains("is-exiting")) return

    event.target.classList.remove("is-exiting")
    this.currentIndex = this.nextIndex
    this.nextIndex = null
    const nextWord = this.wordTargets[this.currentIndex]
    nextWord.classList.add("is-entering")

    this.frameId = requestAnimationFrame(() => {
      nextWord.classList.remove("is-entering")
      nextWord.classList.add("is-active")
      this.frameId = null
      this.isTransitioning = false
    })
  }

  showStaticWord() {
    this.wordTargets.forEach((word, index) => {
      word.classList.remove("is-entering", "is-exiting", "is-active")
      if (index === 0) word.classList.add("is-active")
    })
    this.currentIndex = 0
    this.nextIndex = null
    this.isTransitioning = false
  }

  motionPreferenceChanged() {
    if (this.motionPreference.matches) {
      this.stopRotation()
      if (this.frameId !== null) cancelAnimationFrame(this.frameId)
      this.frameId = null
      this.showStaticWord()
    } else {
      this.startRotation()
    }
  }
}
