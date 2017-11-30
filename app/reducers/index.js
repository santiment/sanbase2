import { combineReducers } from 'redux'
import user, { initialState as userState } from './user'

export const intitialState = {
  user: userState
}

export default combineReducers({
  user
})
