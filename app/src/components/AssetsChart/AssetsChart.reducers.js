import { makeIntervalBounds } from './utils'
import moment from 'moment'
// Actions
export const ASSETS_CHART_SELECT_TIMERANGE = '[assets-chart] SELECT_TIMERANGE'
export const ASSETS_CHART_SELECT_CURRENCY = '[assets-chart] SELECT_CURRENCY'

export const selectTimeRange = ({ timeRange }) => {
  const { from, to, minInterval } = makeIntervalBounds(timeRange)
  let interval = minInterval
  const diffInDays = moment(to).diff(from, 'days')
  if (diffInDays > 32 && diffInDays < 900) {
    interval = '1d'
  } else if (diffInDays >= 900) {
    interval = '1w'
  }
  return {
    timeRange,
    interval,
    from,
    to,
    type: ASSETS_CHART_SELECT_TIMERANGE
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
        timeRange: action.timeRange,
        from: action.from,
        to: action.to,
        interval: action.interval
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
