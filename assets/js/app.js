import "phoenix_html"
// Establish Phoenix Socket and LiveView configuration.
import { Socket } from "phoenix"
import { LiveSocket } from "phoenix_live_view"
import topbar from "../vendor/topbar"
import Alpine from 'alpinejs'
import { FocusInput } from "./focus_input"
import Sortable from 'sortablejs'
import { Sortable as SortableHook } from "./metric_hooks"
import { InfiniteScroll } from "./infinite_scroll"
import { TickerAutocomplete } from "./ticker_autocomplete"
import { EasyMDEEditor } from "./hooks/easymde_editor"

// Make Sortable available globally
window.Sortable = Sortable

window.Alpine = Alpine
Alpine.start()

const Hooks = { 
  FocusInput: FocusInput,
  Sortable: SortableHook,
  InfiniteScroll: InfiniteScroll,
  TickerAutocomplete: TickerAutocomplete,
  EasyMDEEditor: EasyMDEEditor
}

let csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")
let liveSocket = new LiveSocket("/live", Socket, {
  params: { _csrf_token: csrfToken },
  hooks: Hooks,
  dom: {
    onBeforeElUpdated(from, to) {
      if (from._x_dataStack) {
        window.Alpine.clone(from, to)
      }
    }
  }
})

// Theme persistence: applies stored theme on load and saves changes from the toggle.
const applyStoredTheme = () => {
  const stored = localStorage.getItem("theme")
  if (stored === "dark" || stored === "light") {
    document.documentElement.setAttribute("data-theme", stored)
    const ctrl = document.getElementById("theme-controller")
    if (ctrl) ctrl.checked = stored === "dark"
  }
}
applyStoredTheme()
document.addEventListener("change", e => {
  if (e.target && e.target.id === "theme-controller") {
    const theme = e.target.checked ? "dark" : "light"
    document.documentElement.setAttribute("data-theme", theme)
    localStorage.setItem("theme", theme)
  }
})
window.addEventListener("phx:page-loading-stop", applyStoredTheme)

// Show progress bar on live navigation and form submits
topbar.config({ barColors: { 0: "#29d" }, shadowColor: "rgba(0, 0, 0, .3)" })
window.addEventListener("phx:page-loading-start", _info => topbar.show(300))
window.addEventListener("phx:page-loading-stop", _info => topbar.hide())

// Native <dialog class="modal"> open/close. CoreComponents.show_modal/2 and
// hide_modal/2 dispatch these events on the dialog element.
const handleDialogClose = e => {
  const el = e.target
  const cancel = el.dataset && el.dataset.cancel
  if (cancel) liveSocket.execJS(el, cancel)
}
window.addEventListener("phx:show-modal", e => {
  const el = e.target
  if (!el || typeof el.showModal !== "function") return
  if (!el.dataset.dialogListenersBound) {
    el.addEventListener("cancel", handleDialogClose)
    el.addEventListener("close", handleDialogClose)
    el.dataset.dialogListenersBound = "1"
  }
  if (!el.open) el.showModal()
})
window.addEventListener("phx:hide-modal", e => {
  const el = e.target
  if (el && typeof el.close === "function" && el.open) el.close()
})

// connect if there are any LiveViews on the page
liveSocket.connect()

// expose liveSocket on window for web console debug logs and latency simulation:
// >> liveSocket.enableDebug()
// >> liveSocket.enableLatencySim(1000)  // enabled for duration of browser session
// >> liveSocket.disableLatencySim()
window.liveSocket = liveSocket
