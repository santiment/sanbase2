// Actions
export const ASSETS_CHART_SELECT_TIMERANGE = '[assets-chart] SELECT_TIMERANGE'
export const ASSETS_CHART_SELECT_CURRENCY = '[assets-chart] SELECT_CURRENCY'

export const selectTimeRange = timeRange => {
  return {
    timeRange,
    type: ASSETS_CHART_SELECT_TIMERANGE,
    from: '0',
    to: '0',
    interval: '1d'
  }
}

export const selectCurrency = currency => ({
  currency,
  type: ASSETS_CHART_SELECT_CURRENCY
})

// Reducers

export const initialState = {
  timeRange: 'all',
  currency: 'USD'
}

export default (state = initialState, action) => {
  switch (action.type) {
    case ASSETS_CHART_SELECT_TIMERANGE:
      return {
        ...state,
        timeRange: action.timeRange
      }
    case ASSETS_CHART_SELECT_CURRENCY:
      return {
        ...state,
        currency: action.currency
      }
    default:
      return state
  }
}
