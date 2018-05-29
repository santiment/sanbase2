import 'rxjs'
import { combineEpics } from 'redux-observable'
import handleFollowProject from './handleFollowProject'
import handleOffline from './handleOffline'

export default combineEpics(
  handleFollowProject,
  handleOffline
)
