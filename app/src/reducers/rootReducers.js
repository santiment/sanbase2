import { combineReducers } from 'redux'
import { notificationReducer } from 'react-notification-redux';
import user, { initialState as userState } from './user'
import projects, { initialState as projectsState } from './projects'
import detailedPageUi, { initialState as detailedPageUiState } from './detailed-page-ui'
import insightsPageUi, { initialState as insightsPageUiState } from './insights-page-ui'

export const intitialState = {
  user: userState,
  projects: projectsState,
  detailedPageUi: detailedPageUiState,
  insightsPageUi: insightsPageUiState
}

export default combineReducers({
  user,
  projects,
  detailedPageUi,
  insightsPageUi,
  notification: notificationReducer
})
