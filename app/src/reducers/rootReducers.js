import { combineReducers } from 'redux'
import user, { initialState as userState } from './user'
import projects, { initialState as projectsState } from './projects'
import rootUi, { initialState as rootUiState } from './root-ui'
import detailedPageUi, { initialState as detailedPageUiState } from './detailed-page-ui'
import insightsPageUi, { initialState as insightsPageUiState } from './insights-page-ui'
import notification, { initialState as initialNotificationState } from './notification'

export const intitialState = {
  user: userState,
  projects: projectsState,
  detailedPageUi: detailedPageUiState,
  insightsPageUi: insightsPageUiState,
  rootUi: rootUiState,
  notification: initialNotificationState
}

export default combineReducers({
  user,
  projects,
  rootUi,
  detailedPageUi,
  insightsPageUi,
  notification
})
