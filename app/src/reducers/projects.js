export const initialState = {
  isLoading: true,
  error: false,
  ethPrice: null,
  items: [],
  search: {
    value: null,
    visibleItems: 0
  }
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
        search: {
          value: null,
          visibleItems: items.length
        }
      }
    case 'FAILED_PROJECTS':
      return {
        ...state,
        isLoading: false,
        error: true
      }
    case 'SET_SEARCH':
      const visibleItems = (items !== null) ? state.items.filter((item) => {
        return item.name.toLowerCase().indexOf(action.payload.search) !== -1 ||
          item.ticker.toLowerCase().indexOf(action.payload.search) !== -1
      }).length : 0

      return {
        ...state,
        search: {
          value: action.payload.search,
          visibleItems: visibleItems
        }
      }
    default:
      return state
  }
}
