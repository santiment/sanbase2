import { combineReducers } from 'redux'
import { routerReducer } from 'react-router-redux'
import user, { initialState as userState } from './user'
import projects, { initialState as projectsState } from './projects'
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
import assetsListUI, {
  initialState as initialAssetsListUIState
} from './assets-list-ui'

export const intitialState = {
  user: userState,
  projects: projectsState,
  detailedPageUi: detailedPageUiState,
  insightsPageUi: insightsPageUiState,
  assetsListUI: initialAssetsListUIState,
  rootUi: rootUiState,
  notification: initialNotificationState,
  router: routerReducer
}

export default combineReducers({
  user,
  projects,
  rootUi,
  detailedPageUi,
  insightsPageUi,
  assetsListUI,
  notification
})
