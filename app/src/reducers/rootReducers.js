import { combineReducers } from 'redux'
import user, { initialState as userState } from './user'
import projects, { initialState as projectsState } from './projects'
import detailedPageUi, { initialState as detailedPageUiState } from './detailed-page-ui'

export const intitialState = {
  user: userState,
  projects: projectsState,
  detailedPageUi: detailedPageUiState
}

export default combineReducers({
  user,
  projects,
  detailedPageUi
})
