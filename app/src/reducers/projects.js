export const initialState = {
  isLoading: true,
  error: false,
  ethPrice: null,
  items: []
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
        ethPrice: action.payload.data.eth_price
      }
    case 'FAILED_PROJECTS':
      return {
        ...state,
        isLoading: false,
        error: true
      }
    default:
      return state
  }
}
