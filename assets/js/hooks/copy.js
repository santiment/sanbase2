// Copies the text in the element's `data-copy` attribute to the clipboard and
// briefly flips the button into a "Copied" state (driven by the `copied` class,
// which CSS uses to swap the icon/label).
//
// navigator.clipboard exists only in secure contexts (https or localhost). The
// admin panel is served over plain http on the VPN, so there the hook falls
// back to a hidden textarea + execCommand. The "Copied" state only shows when
// a copy actually succeeded.
export const Copy = {
  mounted() {
    this.el.addEventListener("click", () => {
      const text = this.el.dataset.copy || ""
      copyText(text).then((ok) => {
        if (!ok) return
        this.el.classList.add("copied")
        clearTimeout(this._t)
        this._t = setTimeout(() => this.el.classList.remove("copied"), 1500)
      })
    })
  },
}

function copyText(text) {
  if (window.isSecureContext && navigator.clipboard) {
    return navigator.clipboard
      .writeText(text)
      .then(() => true)
      .catch(() => legacyCopy(text))
  }
  return Promise.resolve(legacyCopy(text))
}

function legacyCopy(text) {
  const ta = document.createElement("textarea")
  ta.value = text
  ta.setAttribute("readonly", "")
  // Off-screen, not display:none — a hidden element cannot be selected.
  ta.style.position = "fixed"
  ta.style.top = "-1000px"
  ta.style.opacity = "0"
  document.body.appendChild(ta)
  ta.select()
  let ok = false
  try {
    ok = document.execCommand("copy")
  } catch (_e) {
    ok = false
  }
  document.body.removeChild(ta)
  return ok
}
