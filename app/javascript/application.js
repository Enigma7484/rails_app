// Configure your import map in config/importmap.rb. Read more: https://github.com/rails/importmap-rails
import "@hotwired/turbo-rails"
import "controllers"
import "chartkick"
import "Chart.bundle"

const THEME_KEY = "billsAgent.theme"
const PANEL_ALPHA_KEY = "billsAgent.panelAlpha"
const BLUR_KEY = "billsAgent.blur"

function applyTheme(theme, alpha, blur) {
  if (theme === "default") theme = "dark"
  document.documentElement.dataset.theme = theme
  document.documentElement.style.setProperty("--theme-panel-alpha", alpha)
  document.documentElement.style.setProperty("--theme-blur", `${blur}px`)
}

function currentThemeState() {
  const savedTheme = localStorage.getItem(THEME_KEY) || "terminal"

  return {
    theme: savedTheme === "default" ? "dark" : savedTheme,
    alpha: localStorage.getItem(PANEL_ALPHA_KEY) || "0.66",
    blur: localStorage.getItem(BLUR_KEY) || "18"
  }
}

function syncThemeControls() {
  const settings = document.querySelector("[data-theme-settings]")
  if (!settings) return
  if (settings.dataset.themeSettingsBound === "true") return
  settings.dataset.themeSettingsBound = "true"

  const state = currentThemeState()
  const themeSelect = settings.querySelector("[data-theme-select]")
  const alphaInput = settings.querySelector("[data-panel-alpha]")
  const blurInput = settings.querySelector("[data-panel-blur]")

  themeSelect.value = state.theme
  alphaInput.value = state.alpha
  blurInput.value = state.blur

  const preview = () => applyTheme(themeSelect.value, alphaInput.value, blurInput.value)

  themeSelect.addEventListener("change", preview)
  alphaInput.addEventListener("input", preview)
  blurInput.addEventListener("input", preview)

  settings.querySelector("[data-theme-save]").addEventListener("click", () => {
    localStorage.setItem(THEME_KEY, themeSelect.value)
    localStorage.setItem(PANEL_ALPHA_KEY, alphaInput.value)
    localStorage.setItem(BLUR_KEY, blurInput.value)
    applyTheme(themeSelect.value, alphaInput.value, blurInput.value)
  })

  settings.querySelector("[data-theme-reset]").addEventListener("click", () => {
    themeSelect.value = "terminal"
    alphaInput.value = "0.66"
    blurInput.value = "18"
    localStorage.setItem(THEME_KEY, themeSelect.value)
    localStorage.setItem(PANEL_ALPHA_KEY, alphaInput.value)
    localStorage.setItem(BLUR_KEY, blurInput.value)
    applyTheme(themeSelect.value, alphaInput.value, blurInput.value)
  })
}

document.addEventListener("turbo:load", () => {
  const state = currentThemeState()
  applyTheme(state.theme, state.alpha, state.blur)
  syncThemeControls()
})
