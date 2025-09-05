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
import { TickerAutocomplete } from "./ticker_autocomplete"

// Monaco Editor Hook
const MonacoEditor = {
  mounted() {
    this.initializeMonaco()
  },
  initializeMonaco() {
    const targetId = this.el.dataset.targetInput
    const targetInput = document.getElementById(targetId)
    const initialValue = targetInput ? targetInput.value : ''

    // Load Monaco from CDN
    const requireScriptId = 'monaco-require'
    const loaderScriptId = 'monaco-loader'
    const existingRequire = document.getElementById(requireScriptId)
    const existingLoader = document.getElementById(loaderScriptId)

    const startEditor = () => {
      /* global require */
      require.config({ paths: { vs: 'https://unpkg.com/monaco-editor@0.45.0/min/vs' } })
      require(['vs/editor/editor.main'], () => {
        /* global monaco */
        this.editor = monaco.editor.create(this.el, {
          value: initialValue,
          language: 'markdown',
          theme: 'vs',
          automaticLayout: true,
          minimap: { enabled: false },
          scrollBeyondLastLine: false,
          wordWrap: 'on',
          fontSize: 14,
          lineNumbers: 'on',
          folding: true,
          bracketMatching: 'always',
          autoIndent: 'full',
          cursorStyle: 'line',
          cursorBlinking: 'smooth',
          renderLineHighlight: 'all',
          renderLineHighlightOnlyWhenFocus: false
        })

        // Sync changes to hidden input
        this.editor.onDidChangeModelContent(() => {
          if (targetInput) {
            targetInput.value = this.editor.getValue()
            targetInput.dispatchEvent(new Event('input', { bubbles: true }))
          }
        })
      })
    }

    const ensureMonacoLoader = () => {
      if (!existingRequire) {
        const s = document.createElement('script')
        s.id = requireScriptId
        s.src = 'https://unpkg.com/monaco-editor@0.45.0/min/vs/loader.js'
        s.onload = startEditor
        document.head.appendChild(s)
        return
      }
      // If loader already present, just start
      startEditor()
    }

    // Some CDN builds require AMD loader. Ensure it's present
    if (!window.require) {
      ensureMonacoLoader()
    } else {
      startEditor()
    }
  },
  destroyed() {
    if (this.editor) {
      this.editor.dispose()
    }
  }
}

// Make Sortable available globally
window.Sortable = Sortable

window.Alpine = Alpine
Alpine.start()

const Hooks = { 
  FocusInput: FocusInput,
  Sortable: SortableHook,
  InfiniteScroll: InfiniteScroll,
  TickerAutocomplete: TickerAutocomplete,
  MonacoEditor: MonacoEditor
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
