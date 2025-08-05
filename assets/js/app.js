import "phoenix_html"
// Establish Phoenix Socket and LiveView configuration.
import { Socket } from "phoenix"
import { LiveSocket } from "phoenix_live_view"
import topbar from "../vendor/topbar"
import Alpine from 'alpinejs'
import "flowbite/dist/flowbite.phoenix.js";
import { FocusInput } from "./focus_input"
import Sortable from 'sortablejs'
import { Sortable as SortableHook } from "./metric_hooks"
import { InfiniteScroll } from "./infinite_scroll"

// Make Sortable available globally
window.Sortable = Sortable

window.Alpine = Alpine
Alpine.start()
const Hooks = { 
  FocusInput: FocusInput,
  Sortable: SortableHook,
  InfiniteScroll: InfiniteScroll
}

// Ticker autocomplete hook
Hooks.TickerAutocomplete = {
  mounted() {
    this.handleEvent("ticker_suggestions", (payload) => {
      const { field, suggestions } = payload
      this.showSuggestions(field, suggestions)
    })
  },
  
  showSuggestions(field, suggestions) {
    // Find the suggestions container for this specific field
    // IDs are in format: base_asset_suggestions_1234 or quote_asset_suggestions_1234
    const container = document.querySelector(`[id^="${field}_suggestions_"]`)
    
    if (!container) return
    
    if (suggestions.length === 0) {
      container.classList.add('hidden')
      return
    }
    
    // Create suggestion items
    const suggestionItems = suggestions.map(ticker => 
      `<div class="px-3 py-2 hover:bg-gray-100 cursor-pointer text-sm border-b border-gray-100 last:border-b-0" data-ticker="${ticker}">
        ${ticker}
      </div>`
    ).join('')
    
    container.innerHTML = suggestionItems
    container.classList.remove('hidden')
    
    // Add click handlers for suggestions
    container.querySelectorAll('[data-ticker]').forEach(item => {
      item.addEventListener('click', (e) => {
        const ticker = e.target.getAttribute('data-ticker')
        // Find the corresponding input field by replacing _suggestions_ with _
        const inputId = container.id.replace('_suggestions_', '_')
        const input = document.getElementById(inputId)
        if (input) {
          input.value = ticker
          container.classList.add('hidden')
        }
      })
    })
  }
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

// Show progress bar on live navigation and form submits
topbar.config({ barColors: { 0: "#29d" }, shadowColor: "rgba(0, 0, 0, .3)" })
window.addEventListener("phx:page-loading-start", _info => topbar.show(300))
window.addEventListener("phx:page-loading-stop", _info => topbar.hide())

// connect if there are any LiveViews on the page
liveSocket.connect()

// expose liveSocket on window for web console debug logs and latency simulation:
// >> liveSocket.enableDebug()
// >> liveSocket.enableLatencySim(1000)  // enabled for duration of browser session
// >> liveSocket.disableLatencySim()
window.liveSocket = liveSocket
