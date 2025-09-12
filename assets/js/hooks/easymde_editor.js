export const EasyMDEEditor = {
  mounted() {
    this.initializeEasyMDE()
  },
  initializeEasyMDE() {
    const targetInput = document.getElementById(this.el.dataset.targetInput)
    const initialValue = targetInput ? targetInput.value : ''
    const textarea = this.el.querySelector('textarea') || this.el

    textarea.value = initialValue

    const hook = this
    this.loadEasyMDE(() => {
      /* global EasyMDE */
      this.editor = new EasyMDE({
        element: textarea,
        spellChecker: false,
        autofocus: false,
        placeholder: 'Enter your markdown here...',
        previewRender: (plainText, previewEl) => {
          if (!hook || !hook.pushEvent) return plainText
          if (previewEl) {
            previewEl.classList.add('prose', 'max-w-none')
            previewEl.innerHTML = '<div class="text-gray-400">Rendering preview…</div>'
          }
          hook.pushEvent('render_markdown', { markdown: plainText }, (resp) => {
            if (previewEl && resp && typeof resp.html === 'string') {
              previewEl.innerHTML = resp.html
            }
          })
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

      this.editor.codemirror.on('change', () => {
        if (targetInput) {
          targetInput.value = this.editor.value()
          targetInput.dispatchEvent(new Event('input', { bubbles: true }))
        }
      })
    })
  },
  loadEasyMDE(callback) {
    if (window.EasyMDE) {
      callback()
      return
    }

    if (!document.querySelector('link[href*="easymde"]')) {
      const css = document.createElement('link')
      css.rel = 'stylesheet'
      css.href = 'https://cdn.jsdelivr.net/npm/easymde/dist/easymde.min.css'
      document.head.appendChild(css)
    }

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


