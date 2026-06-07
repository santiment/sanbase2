// Copies the text in the element's `data-copy` attribute to the clipboard and
// briefly flips the button into a "Copied" state (driven by the `copied` class,
// which CSS uses to swap the icon/label).
export const Copy = {
  mounted() {
    this.el.addEventListener("click", () => {
      const text = this.el.dataset.copy || ""
      navigator.clipboard.writeText(text).then(() => {
        this.el.classList.add("copied")
        clearTimeout(this._t)
        this._t = setTimeout(() => this.el.classList.remove("copied"), 1500)
      }).catch(() => {})
    })
  }
}
