const board = document.querySelector("[data-board-url]")

if (board) {
  const csrfToken = document.querySelector("meta[name=csrf-token]")?.content
  let dragged = null
  let origin = null
  let dropped = false

  // The whole column section (heading included) is a drop target; cards live in its [data-column] list.
  const listFor = (target) => target.closest?.("section")?.querySelector("[data-column]") ?? null

  const save = async (list, card) => {
    const issueIds = [...list.querySelectorAll(".shiplog-card")].map((el) => Number(el.dataset.issueId))
    const response = await fetch(board.dataset.boardUrl, {
      method: "PATCH",
      headers: { "Content-Type": "application/json", "Accept": "application/json", "X-CSRF-Token": csrfToken },
      body: JSON.stringify({ column: list.dataset.column, moved_id: Number(card.dataset.issueId), issue_ids: issueIds })
    })
    if (!response.ok) window.location.reload()
  }

  const cardAfter = (list, y) => {
    const cards = [...list.querySelectorAll(".shiplog-card:not(.shiplog-card--dragging)")]
    return cards.find((card) => {
      const box = card.getBoundingClientRect()
      return y < box.top + box.height / 2
    })
  }

  const restore = () => {
    const { parent, nextSibling } = origin
    parent.insertBefore(dragged, nextSibling?.parentNode === parent ? nextSibling : null)
  }

  board.addEventListener("dragstart", (event) => {
    const card = event.target.closest?.(".shiplog-card")
    if (!card) return
    dragged = card
    origin = { parent: card.parentNode, nextSibling: card.nextSibling }
    dropped = false
    event.dataTransfer.setData("text/plain", card.dataset.issueId)
    event.dataTransfer.effectAllowed = "move"
    card.classList.add("shiplog-card--dragging")
  })

  board.addEventListener("dragend", () => {
    if (!dragged) return
    dragged.classList.remove("shiplog-card--dragging")
    if (!dropped) restore()
    dragged = null
    origin = null
    dropped = false
  })

  board.addEventListener("dragover", (event) => {
    const list = listFor(event.target)
    if (!dragged || !list) return
    event.preventDefault()
    event.dataTransfer.dropEffect = "move"
    list.insertBefore(dragged, cardAfter(list, event.clientY) ?? null)
  })

  board.addEventListener("drop", (event) => {
    const list = listFor(event.target)
    if (!dragged || !list) return
    event.preventDefault()
    dropped = true
    save(list, dragged).catch(() => window.location.reload())
  })
}
