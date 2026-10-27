// Forms marked data-shiplog-once (the newsletter's Send, Send test and Retry) submit once: their buttons are
// disabled and marked busy as soon as the form is submitted, so a double click sends one request. The server is
// idempotent anyway (delivery rows are claimed atomically); this only spares the admin a confusing second request.
// Buttons come back when the page is restored from the back/forward cache.
const SELECTOR = "form[data-shiplog-once]"

document.addEventListener("submit", (event) => {
  const form = event.target
  if (!(form instanceof HTMLFormElement) || !form.matches(SELECTOR)) return

  if (form.dataset.shiplogSubmitted === "true") {
    event.preventDefault()
    return
  }
  form.dataset.shiplogSubmitted = "true"
  form.setAttribute("aria-busy", "true")
  // Disabled after the submit event, so the clicked button's name and value are still sent.
  setTimeout(() => {
    form.querySelectorAll("button, input[type=submit]").forEach((button) => { button.disabled = true })
  }, 0)
})

window.addEventListener("pageshow", (event) => {
  if (!event.persisted) return

  document.querySelectorAll(SELECTOR).forEach((form) => {
    delete form.dataset.shiplogSubmitted
    form.removeAttribute("aria-busy")
    form.querySelectorAll("button, input[type=submit]").forEach((button) => { button.disabled = false })
  })
})
