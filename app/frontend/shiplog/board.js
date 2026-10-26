const board = document.querySelector("[data-board-url]")

if (board) {
  const csrfToken = document.querySelector("meta[name=csrf-token]")?.content
  let dragged = null

  const columnOf = (card) => card.closest("[data-column]")

  const save = async (column) => {
    const issueIds = [...column.querySelectorAll(".shiplog-card")].map((card) => Number(card.dataset.issueId))
    const response = await fetch(board.dataset.boardUrl, {
      method: "PATCH",
      headers: { "Content-Type": "application/json", "Accept": "application/json", "X-CSRF-Token": csrfToken },
      body: JSON.stringify({ column: column.dataset.column, issue_ids: issueIds })
    })
    if (!response.ok) window.location.reload()
  }

  const cardAfter = (column, y) => {
    const cards = [...column.querySelectorAll(".shiplog-card:not(.shiplog-card--dragging)")]
    return cards.find((card) => {
      const box = card.getBoundingClientRect()
      return y < box.top + box.height / 2
    })
  }

  board.addEventListener("dragstart", (event) => {
    dragged = event.target.closest(".shiplog-card")
    if (!dragged) return
    event.dataTransfer.effectAllowed = "move"
    dragged.classList.add("shiplog-card--dragging")
  })

  board.addEventListener("dragend", () => {
    dragged?.classList.remove("shiplog-card--dragging")
    dragged = null
  })

  board.addEventListener("dragover", (event) => {
    const column = event.target.closest("[data-column]")
    if (!dragged || !column) return
    event.preventDefault()
    column.insertBefore(dragged, cardAfter(column, event.clientY) ?? null)
  })

  board.addEventListener("drop", (event) => {
    const column = event.target.closest("[data-column]")
    if (!dragged || !column) return
    event.preventDefault()
    save(columnOf(dragged)).catch(() => window.location.reload())
  })
}
