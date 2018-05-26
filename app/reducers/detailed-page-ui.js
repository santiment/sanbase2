export const initialState = {
  isFullscreenMobile: false,
  isToggledMinimap: false,
  isToggledBurnRate: false,
  timeFilter: {
    timeframe: 'all',
    from: undefined,
    to: undefined,
    interval: '1d'
  }
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
    case 'CHANGE_TIME_FILTER':
      const { timeframe, from, to, interval } = action
      return {
        ...state,
        timeFilter: {
          timeframe,
          from,
          to,
          interval
        }
      }
    case 'TOGGLE_FOLLOW':
      return {
        ...state
      }
    default:
      return state
  }
}
