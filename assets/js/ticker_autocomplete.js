export const TickerAutocomplete = {
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