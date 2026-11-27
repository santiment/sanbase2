// Publishes the sticky plan bar's height as `--plan-bar-h` on the document, so
// the sticky table header can sit directly under it. The bar's height changes
// when its controls wrap (narrow windows, the compare view's wider channel
// toggle), so it is measured on every resize of the bar.
export const PlanBarHeight = {
  mounted() {
    this.publish = () => {
      const height = Math.ceil(this.el.getBoundingClientRect().height)
      document.documentElement.style.setProperty("--plan-bar-h", `${height}px`)
    }

    // Below md the plan options scroll sideways in one row: bring the selected
    // one into view, without scrolling the page.
    this.revealSelected = () => {
      const selected = this.el.querySelector("#plan-picker [aria-current=true]")
      const row = selected && selected.parentElement
      if (!row || row.scrollWidth <= row.clientWidth) return
      const left = selected.offsetLeft - row.offsetLeft
      row.scrollLeft = left - (row.clientWidth - selected.offsetWidth) / 2
    }

    this.publish()
    this.revealSelected()
    this.observer = new ResizeObserver(this.publish)
    this.observer.observe(this.el)
  },

  updated() {
    this.publish()
    this.revealSelected()
  },

  destroyed() {
    if (this.observer) this.observer.disconnect()
    this.observer = null
    document.documentElement.style.removeProperty("--plan-bar-h")
  },
}
