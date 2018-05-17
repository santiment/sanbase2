export const initialState = {
  isFullscreenMobile: false,
  isToggledMinimap: false,
  isToggledBurnRate: false
}

export default (state = initialState, action) => {
  switch (action.type) {
    case 'TOGGLE_FULLSCREEN_MOBILE':
      return {
        ...state,
        isFullscreenMobile: !state.isFullscreenMobile
      }
    case 'TOGGLE_MINIMAP':
      return {
        ...state,
        isToggledMinimap: !state.isToggledMinimap
      }
    case 'TOGGLE_BURNRATE':
      return {
        ...state,
        isToggledBurnRate: !state.isToggledBurnRate
      }
    default:
      return state
  }
}
