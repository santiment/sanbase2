import { combineReducers } from 'redux'
import { notificationReducer } from 'react-notification-redux';
import user, { initialState as userState } from './user'
import projects, { initialState as projectsState } from './projects'

export const intitialState = {
  user: userState,
  projects: projectsState
}

export default combineReducers({
  user,
  projects
})
