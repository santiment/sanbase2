// Preserve a <details> element's open/closed state across LiveView DOM patches.
//
// A <details> toggle is browser-side DOM state the server doesn't know about. When a
// new item streams into the group (e.g. another tool call), LiveView re-renders the
// element and morphdom reconciles attributes — the server HTML has no `open`, so the
// user's expanded state is stripped and the section snaps shut. This hook records the
// user's toggle in a page-lifetime store (keyed by the element's stable id) and
// re-applies it after every patch, so an expanded section stays expanded.
//
// Requires the element to carry a STABLE id across re-renders.

const openState = {}

export const KeepDetailsOpen = {
  mounted() {
    this.el.addEventListener("toggle", () => {
      openState[this.el.id] = this.el.open
    })
    this.apply()
  },
  updated() {
    this.apply()
  },
  apply() {
    const want = openState[this.el.id]
    if (want !== undefined && this.el.open !== want) {
      this.el.open = want
    }
  }
}
