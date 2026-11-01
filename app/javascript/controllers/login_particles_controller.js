import { Controller } from "@hotwired/stimulus"

const COLORS = ["#4F56D9", "#25C5A7", "#FFFFFF"]
const REDUCED_MOTION_QUERY = "(prefers-reduced-motion: reduce)"

export default class extends Controller {
  static targets = ["canvas"]

  connect() {
    this.canvasContext = this.canvasTarget.getContext("2d")
    if (!this.canvasContext) return

    this.particles = []
    this.frameId = null
    this.pointer = { x: 0, y: 0, active: false }
    this.motionPreference = window.matchMedia(REDUCED_MOTION_QUERY)
    this.handleResize = this.resize.bind(this)
    this.handlePointerMove = this.pointerMove.bind(this)
    this.handlePointerLeave = this.pointerLeave.bind(this)
    this.handleMotionPreferenceChange = this.motionPreferenceChanged.bind(this)

    if (window.ResizeObserver) {
      this.resizeObserver = new ResizeObserver(this.handleResize)
      this.resizeObserver.observe(this.element)
    } else {
      window.addEventListener("resize", this.handleResize)
    }

    this.element.addEventListener("pointermove", this.handlePointerMove, { passive: true })
    this.element.addEventListener("pointerleave", this.handlePointerLeave)
    this.motionPreference.addEventListener("change", this.handleMotionPreferenceChange)

    this.resize()
    if (this.motionPreference.matches) {
      this.draw()
    } else {
      this.animate()
    }
  }

  disconnect() {
    if (this.frameId !== null) cancelAnimationFrame(this.frameId)
    this.frameId = null
    this.resizeObserver?.disconnect()
    window.removeEventListener("resize", this.handleResize)
    this.element.removeEventListener("pointermove", this.handlePointerMove)
    this.element.removeEventListener("pointerleave", this.handlePointerLeave)
    this.motionPreference?.removeEventListener("change", this.handleMotionPreferenceChange)
  }

  resize() {
    const bounds = this.element.getBoundingClientRect()
    this.width = bounds.width
    this.height = bounds.height
    this.pixelRatio = Math.min(window.devicePixelRatio || 1, 2)
    this.canvasTarget.width = Math.round(this.width * this.pixelRatio)
    this.canvasTarget.height = Math.round(this.height * this.pixelRatio)
    this.canvasContext.setTransform(this.pixelRatio, 0, 0, this.pixelRatio, 0, 0)

    const areaBasedCount = Math.floor((this.width * this.height) / 12000)
    const maxParticles = this.width <= 768 ? 54 : 120
    const particleCount = Math.max(24, Math.min(maxParticles, areaBasedCount))
    this.particles = Array.from({ length: particleCount }, () => this.createParticle())

    if (this.motionPreference.matches) this.draw()
  }

  createParticle() {
    const angle = Math.random() * Math.PI * 2
    const speed = 0.08 + Math.random() * 0.18

    return {
      x: Math.random() * this.width,
      y: Math.random() * this.height,
      radius: 0.7 + Math.random() * 1.5,
      alpha: 0.2 + Math.random() * 0.35,
      color: COLORS[Math.floor(Math.random() * COLORS.length)],
      velocityX: Math.cos(angle) * speed,
      velocityY: Math.sin(angle) * speed
    }
  }

  animate() {
    this.draw(true)
    this.frameId = requestAnimationFrame(() => this.animate())
  }

  draw(advance = false) {
    this.canvasContext.clearRect(0, 0, this.width, this.height)

    this.particles.forEach((particle) => {
      if (advance) this.advanceParticle(particle)

      let x = particle.x
      let y = particle.y
      if (this.pointer.active) {
        const offsetX = x - this.pointer.x
        const offsetY = y - this.pointer.y
        const distance = Math.hypot(offsetX, offsetY)
        const influence = Math.max(0, 1 - distance / 140) * 2.5
        if (distance > 0) {
          x += (offsetX / distance) * influence
          y += (offsetY / distance) * influence
        }
      }

      this.canvasContext.globalAlpha = particle.alpha
      this.canvasContext.fillStyle = particle.color
      this.canvasContext.beginPath()
      this.canvasContext.arc(x, y, particle.radius, 0, Math.PI * 2)
      this.canvasContext.fill()
    })

    this.canvasContext.globalAlpha = 1
  }

  advanceParticle(particle) {
    particle.x += particle.velocityX
    particle.y += particle.velocityY

    if (particle.x < -2) particle.x = this.width + 2
    if (particle.x > this.width + 2) particle.x = -2
    if (particle.y < -2) particle.y = this.height + 2
    if (particle.y > this.height + 2) particle.y = -2
  }

  pointerMove(event) {
    const bounds = this.element.getBoundingClientRect()
    this.pointer.x = event.clientX - bounds.left
    this.pointer.y = event.clientY - bounds.top
    this.pointer.active = true
  }

  pointerLeave() {
    this.pointer.active = false
  }

  motionPreferenceChanged() {
    if (this.motionPreference.matches) {
      if (this.frameId !== null) cancelAnimationFrame(this.frameId)
      this.frameId = null
      this.draw()
    } else if (!this.frameId) {
      this.animate()
    }
  }
}
