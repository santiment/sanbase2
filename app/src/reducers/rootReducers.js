import { combineReducers } from 'redux'
import { routerReducer } from 'react-router-redux'
import user, { initialState as userState } from './user'
import projects, { initialState as projectsState } from './projects'
import timeseries, { initialState as timeseriesState } from './timeseries'
import rootUi, { initialState as rootUiState } from './root-ui'
import detailedPageUi, {
  initialState as detailedPageUiState
} from './detailed-page-ui'
import insightsPageUi, {
  initialState as insightsPageUiState
} from './insights-page-ui'
import notification, {
  initialState as initialNotificationState
} from './notification'
import watchlistUi, {
  initialState as initialWatchlistUiState
} from './watchlist-ui'
import hypedTrends, {
  initialState as initialHypedTrends
} from './../components/Trends/reducers'

export const intitialState = {
  user: userState,
  projects: projectsState,
  hypedTrends: initialHypedTrends,
  timeseries: timeseriesState,
  detailedPageUi: detailedPageUiState,
  insightsPageUi: insightsPageUiState,
  watchlistUi: initialWatchlistUiState,
  rootUi: rootUiState,
  notification: initialNotificationState,
  router: routerReducer
}

export default combineReducers({
  user,
  projects,
  hypedTrends,
  timeseries,
  rootUi,
  detailedPageUi,
  insightsPageUi,
  watchlistUi,
  notification
})
