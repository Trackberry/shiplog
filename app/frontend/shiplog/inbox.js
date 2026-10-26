// Idempotent: runs now and again on turbo:load (inert without Turbo), binding each container once.
const init = () => {
  const inbox = document.querySelector("[data-shiplog-inbox]")
  if (!inbox || inbox.dataset.shiplogBound) return
  inbox.dataset.shiplogBound = "true"

  // Host layouts may not render csrf_meta_tags, so the container carries the token as a fallback.
  const csrfToken = document.querySelector("meta[name=csrf-token]")?.content ?? inbox.dataset.csrfToken
  const status = inbox.querySelector("[data-shiplog-status]")
  const reducedMotion = window.matchMedia("(prefers-reduced-motion: reduce)")

  const announce = (text, alert = false) => {
    status.textContent = text
    status.classList.toggle("shiplog-admin__live--alert", alert)
    status.setAttribute("role", alert ? "alert" : "status")
    status.hidden = false
  }

  const showEmptyState = () => {
    const empty = document.createElement("p")
    empty.className = "shiplog-admin__empty"
    empty.textContent = inbox.dataset.emptyText
    inbox.querySelector("table").replaceWith(empty)
  }

  const removeRow = (row) => {
    const done = () => {
      row.remove()
      if (!inbox.querySelector(".shiplog-entry-row")) showEmptyState()
    }
    if (reducedMotion.matches) return done()
    row.classList.add("shiplog-entry-row--leaving")
    row.addEventListener("transitionend", done, { once: true })
    setTimeout(() => row.isConnected && done(), 400)
  }

  const replaceRow = (row, html) => {
    const template = document.createElement("template")
    template.innerHTML = html.trim()
    row.replaceWith(template.content.firstElementChild)
  }

  // Bubbling submit on the container runs before Turbo's document-level listener.
  inbox.addEventListener("submit", async (event) => {
    const form = event.target.closest("form[data-shiplog-inline]")
    if (!form) return
    event.preventDefault()

    const row = form.closest(".shiplog-entry-row")
    const title = row.querySelector("a").textContent.trim()
    const button = event.submitter ?? form.querySelector("button")
    button.disabled = true
    try {
      // Rails reads a hidden _method field (button_to), so the request itself is always a POST.
      const response = await fetch(form.action, {
        method: "POST",
        headers: { "Accept": "application/json", "X-CSRF-Token": csrfToken },
        body: new FormData(form)
      })
      if (response.status !== 200 && response.status !== 422) throw new Error(response.status)

      const data = await response.json()
      if (response.status === 422) {
        button.disabled = false
        return announce(`${title}: ${data.error}`, true)
      }
      announce(`${title}: ${data.message}`)
      if (data.matches_filter) replaceRow(row, data.row)
      else removeRow(row)
    } catch (error) {
      // Network or server failure: fall back to a normal form submission.
      form.submit()
    }
  })
}

init()
document.addEventListener("turbo:load", init)
