// Auto-growing textarea: starts at its CSS min-height (one row) and grows with
// the content up to its CSS max-height, then scrolls. Height is driven from the
// element's scrollHeight; the min-h/max-h utility classes set the bounds.
export const AutoGrow = {
  mounted() {
    this.resize = () => {
      this.el.style.height = "auto"
      this.el.style.height = `${this.el.scrollHeight}px`
    }
    this.el.addEventListener("input", this.resize)
    // Resize once after layout so an initial value renders at the right height.
    requestAnimationFrame(this.resize)
  },
  updated() {
    // LiveView patched the element (e.g. the value was cleared on submit) — refit.
    this.resize()
  },
  destroyed() {
    this.el.removeEventListener("input", this.resize)
  }
}
