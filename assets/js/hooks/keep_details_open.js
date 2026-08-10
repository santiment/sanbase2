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
  destroyed() {
    // The store is page-lifetime; without pruning it grows with every element
    // that ever mounted (timeline resets, session switches). Morphdom patches a
    // same-id element in place rather than destroy/remount, so a destroy really
    // means the element is gone.
    delete openState[this.el.id]
  },
  apply() {
    const want = openState[this.el.id]
    if (want !== undefined && this.el.open !== want) {
      this.el.open = want
    }
  }
}
