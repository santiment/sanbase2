// Pushes "load_more" while the hooked element (the Show more bar under a long
// list) is within 400px of the bottom of the window viewport, one request at a
// time. Remove the element once nothing is left to load.
//
// LiveView's phx-viewport-bottom binds to the nearest ancestor whose computed
// overflow-y is auto/scroll. A table in an `overflow-x-auto` wrapper gets
// overflow-y auto too, so the binding listens on a box that never scrolls
// vertically and never fires. An IntersectionObserver on the window viewport does
// not depend on the layout around the list.
export const LoadMoreOnVisible = {
  mounted() {
    this.loading = false
    this.observer = new IntersectionObserver(
      (entries) => {
        if (entries.some((entry) => entry.isIntersecting)) this.loadMore()
      },
      { rootMargin: "0px 0px 400px 0px" }
    )
    this.observer.observe(this.el)
  },

  // A new search or category resets the list under a bar that may not have moved.
  updated() {
    if (!this.loading) this.recheck()
  },

  destroyed() {
    if (this.observer) this.observer.disconnect()
    this.observer = null
  },

  loadMore() {
    // The observer can report again before the rows land.
    if (this.loading) return
    this.loading = true

    this.pushEvent("load_more", {}, () => {
      this.loading = false
      this.recheck()
    })
  },

  // The observer only reports changes; re-observing makes it report the current
  // state, so a bar still in view (a tall window) loads the next page.
  recheck() {
    if (!this.observer || !this.el.isConnected) return
    this.observer.unobserve(this.el)
    this.observer.observe(this.el)
  },
}
