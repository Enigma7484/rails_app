import { Controller } from "@hotwired/stimulus"

// Local fictional examples only. No requests, storage, or account mutations.
export default class extends Controller {
  static targets = ["tabs", "tab", "panel", "detection", "merchant", "correction", "decision", "potential", "cancelled", "decisionFeedback", "calendar"]

  connect() {
    this.tabsTarget.hidden = false
    this.detectionTarget.id = "sample-detection"
    this.detectionTarget.hidden = true
    this.calendarTarget.hidden = true
    this.element.querySelectorAll("[aria-expanded]").forEach(button => button.setAttribute("aria-expanded", "false"))
    this.merchantTarget.value = "Cloudnest"
    this.correctionTarget.textContent = ""
    this.decisionTarget.value = "keep"
    this.decide()
    this.panelTargets.forEach((panel, index) => {
      panel.setAttribute("role", "tabpanel")
      panel.setAttribute("aria-labelledby", `bill-tab-${index}`)
      panel.tabIndex = 0
    })
    this.activate(0)
  }

  select(event) {
    if (event.type === "click") this.activate(Number(event.currentTarget.dataset.index))
  }

  navigate(event) {
    if (event.type !== "keydown" || !["ArrowLeft", "ArrowRight", "Home", "End"].includes(event.key)) return
    event.preventDefault()
    const current = Number(event.currentTarget.dataset.index)
    const next = event.key === "Home" ? 0 : event.key === "End" ? 3 : (current + (event.key === "ArrowRight" ? 1 : -1) + 4) % 4
    this.activate(next)
    this.tabTargets[next].focus()
  }

  activate(index) {
    this.tabTargets.forEach((tab, position) => {
      tab.setAttribute("aria-selected", String(position === index))
      tab.tabIndex = position === index ? 0 : -1
    })
    this.panelTargets.forEach((panel, position) => { panel.hidden = position !== index })
  }

  detect(event) {
    this.detectionTarget.hidden = !this.detectionTarget.hidden
    event.currentTarget.setAttribute("aria-expanded", String(!this.detectionTarget.hidden))
  }

  correct() {
    const name = this.merchantTarget.value.trim()
    this.correctionTarget.textContent = name ? `Sample corrected to “${name}”. Three monthly charges total $27.00 CAD. No account data was saved.` : "Enter a merchant name to try the correction."
    if (!name) this.merchantTarget.focus()
  }

  decide() {
    const decision = this.decisionTarget.value
    const potential = ["cancel_candidate", "watchlist"].includes(decision)
    const cancelled = decision === "cancelled"
    this.potentialTarget.textContent = potential ? "$18.00" : "$0.00"
    this.cancelledTarget.textContent = cancelled ? "$18.00" : "$0.00"
    const descriptions = {
      keep: "Keep: included in your recurring picture.",
      cancel_candidate: "Cancel candidate: $216.00 CAD annualized potential savings. Next step: cancel with the merchant, then confirm here.",
      watchlist: "Watchlist: $216.00 CAD annualized potential savings. Revisit whether you still use it.",
      ignored: "Ignored: excluded from action-plan savings.",
      cancelled: "Marked cancelled: $216.00 CAD annualized savings tracked. This demo has not cancelled any service."
    }
    this.decisionFeedbackTarget.textContent = descriptions[decision]
  }

  calendar(event) {
    this.calendarTarget.hidden = !this.calendarTarget.hidden
    event.currentTarget.setAttribute("aria-expanded", String(!this.calendarTarget.hidden))
  }
}
