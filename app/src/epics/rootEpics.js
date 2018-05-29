import 'rxjs'
import { combineEpics } from 'redux-observable'
import handleFollowProject from './handleFollowProject'

export default combineEpics(
  handleFollowProject
)
