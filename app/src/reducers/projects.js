export const initialState = {
  isLoading: true,
  error: false,
  ethPrice: null,
  items: [],
  tableInfo: {
    visibleItems: 0,
    pageSize: 0,
    page: 1
  },
  search: '',
  categories: {}
}

export default (state = initialState, action) => {
  switch (action.type) {
    case 'LOADING_PROJECTS':
      return {
        ...state,
        isLoading: true
      }
    case 'SUCCESS_PROJECTS':
      const items = action.payload.data.projects.map(project => ({
        ...project,
        ethPrice: action.payload.data.eth_price
      }))
      return {
        ...state,
        isLoading: false,
        error: false,
        items: items,
        ethPrice: action.payload.data.eth_price,
        tableInfo: {
          visibleItems: items.length,
          pageSize: items.length,
          page: 1
        }
      }
    case 'FAILED_PROJECTS':
      return {
        ...state,
        isLoading: false,
        error: true
      }
    case 'SET_SEARCH':
      const visibleItems = (items !== null) ? state.items.filter(item => {
        const name = item.name || ''
        const ticker = item.ticker || ''
        return name.toLowerCase().indexOf(action.payload.search) !== -1 ||
          ticker.toLowerCase().indexOf(action.payload.search) !== -1
      }).length : 0

      return {
        ...state,
        tableInfo: {
          visibleItems: visibleItems,
          pageSize: visibleItems,
          page: 1
        },
        search: action.payload.search
      }
    case 'SET_CATEGORY':
      if (action.payload.category.name === 'clearAllCategories') {
        state.categories = {}
      } else if (!action.payload.category.checked) {
        delete state.categories[action.payload.category.id]
      } else {
        state.categories[action.payload.category.id] = action.payload.category.checked
      }

      return {
        ...state,
        categories: {...state.categories}
      }
    default:
      return state
  }
}
