import 'rxjs'
import { combineEpics } from 'redux-observable'
import handleOffline from './handleOffline'
import handleLauched from './handleLaunch'
import handleLogout from './handleLogout'
import handleEmailLogin, { handleLoginSuccess } from './handleEmailLogin'
import handleEthLogin from './handleEthLogin'
import handleGDPR from './handleGDPR'
import handleRouter from './handleRouter'
import handleApikeyGenerate from './handleApikeyGenerate'
import handleApikeyRevoke from './handleApikeyRevoke'
import handleNightModeToggle from './handleNightModeToggle'
import keyboardEpic from './keyboardEpic'

export default combineEpics(
  handleOffline,
  handleLauched,
  handleLogout,
  handleEmailLogin,
  handleLoginSuccess,
  handleEthLogin,
  handleGDPR,
  handleRouter,
  handleApikeyGenerate,
  handleApikeyRevoke,
  handleNightModeToggle,
  keyboardEpic
)
