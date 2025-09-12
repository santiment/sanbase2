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

// EasyMDE Markdown Editor Hook
const EasyMDEEditor = {
  mounted() {
    this.initializeEasyMDE()
  },
  initializeEasyMDE() {
    const targetInput = document.getElementById(this.el.dataset.targetInput)
    const initialValue = targetInput ? targetInput.value : ''
    const textarea = this.el.querySelector('textarea') || this.el

    // Set initial value to textarea
    textarea.value = initialValue

    // Load EasyMDE CSS and JS from CDN
    const hook = this
    this.loadEasyMDE(() => {
      /* global EasyMDE */
      this.editor = new EasyMDE({
        element: textarea,
        spellChecker: false,
        autofocus: false,
        placeholder: 'Enter your markdown here...',
        previewRender: (plainText, previewEl) => {
          // Defer to LiveView server-side rendering to match Earmark
          if (!hook || !hook.pushEvent) return plainText
          // show temporary content
          if (previewEl) {
            // Ensure Tailwind Typography styles are applied like on show page
            previewEl.classList.add('prose', 'max-w-none')
            previewEl.innerHTML = '<div class="text-gray-400">Rendering preview…</div>'
          }
          hook.pushEvent('render_markdown', { markdown: plainText }, (resp) => {
            if (previewEl && resp && typeof resp.html === 'string') {
              previewEl.innerHTML = resp.html
            }
          })
          // EasyMDE will use the content we set asynchronously
          return ''
        },
        toolbar: [
          'bold', 'italic', 'heading', '|',
          'quote', 'unordered-list', 'ordered-list', '|',
          'link', 'image', 'code', 'table', '|',
          'preview', 'side-by-side', 'fullscreen', '|',
          'guide'
        ],
        shortcuts: {
          toggleBold: 'Cmd-B',
          toggleItalic: 'Cmd-I',
          toggleCodeBlock: 'Cmd-Alt-C',
          togglePreview: 'Cmd-P',
          toggleSideBySide: 'F9',
          toggleFullScreen: 'F11'
        },
        status: ['autosave', 'lines', 'words', 'cursor'],
        tabSize: 2
      })

      // Sync changes to hidden input
      this.editor.codemirror.on('change', () => {
        if (targetInput) {
          targetInput.value = this.editor.value()
          targetInput.dispatchEvent(new Event('input', { bubbles: true }))
        }
      })
    })
  },
  loadEasyMDE(callback) {
    // Check if EasyMDE is already loaded
    if (window.EasyMDE) {
      callback()
      return
    }

    // Load CSS
    if (!document.querySelector('link[href*="easymde"]')) {
      const css = document.createElement('link')
      css.rel = 'stylesheet'
      css.href = 'https://cdn.jsdelivr.net/npm/easymde/dist/easymde.min.css'
      document.head.appendChild(css)
    }

    // Load JS
    if (!document.querySelector('script[src*="easymde"]')) {
      const script = document.createElement('script')
      script.src = 'https://cdn.jsdelivr.net/npm/easymde/dist/easymde.min.js'
      script.onload = callback
      document.head.appendChild(script)
    } else {
      callback()
    }
  },
  destroyed() {
    if (this.editor) {
      this.editor.toTextArea()
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
