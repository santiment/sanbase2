const FocusInput = {
  mounted() {

    document.addEventListener('keyup', (e) => {
      const input = document.getElementById('search-input');
      const search_result = document.getElementById('search-result-suggestions')
      if (document.activeElement != input) {
        if (e.key === '/') {
          input.focus();
          search_result.classList.remove('hidden')
        }
      }
    })
  }
}

export { FocusInput }
