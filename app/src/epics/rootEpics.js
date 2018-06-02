import 'rxjs'
import { combineEpics } from 'redux-observable'
import handleFollowProject from './handleFollowProject'
import handleOffline from './handleOffline'
import handleLauched from './handleLaunch'

export default combineEpics(
  handleFollowProject,
  handleOffline,
  handleLauched
)
