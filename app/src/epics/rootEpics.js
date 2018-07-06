import 'rxjs'
import { combineEpics } from 'redux-observable'
import handleFollowProject from './handleFollowProject'
import handleOffline from './handleOffline'
import handleLauched from './handleLaunch'
import handleEmailLogin, { handleLoginSuccess } from './handleEmailLogin'
import handleEthLogin from './handleEthLogin'
import handleGDPR from './handleGDPR'
import handleRouter from './handleRouter'
import handleApikeyGenerate from './handleApikeyGenerate'
import handleApikeyRevoke from './handleApikeyRevoke'

export default combineEpics(
  handleFollowProject,
  handleOffline,
  handleLauched,
  handleEmailLogin,
  handleLoginSuccess,
  handleEthLogin,
  handleGDPR,
  handleRouter,
  handleApikeyGenerate,
  handleApikeyRevoke
)
