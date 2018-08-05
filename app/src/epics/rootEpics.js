import 'rxjs'
import { combineEpics } from 'redux-observable'
import handleFollowProject from './handleFollowProject'
import handleOffline from './handleOffline'
import handleLauched from './handleLaunch'
import handleLogout from './handleLogout'
import handleEmailLogin, { handleLoginSuccess } from './handleEmailLogin'
import handleEthLogin from './handleEthLogin'
import handleGDPR from './handleGDPR'
import handleRouter from './handleRouter'
import handleApikeyGenerate from './handleApikeyGenerate'
import handleApikeyRevoke from './handleApikeyRevoke'
import addNewAssetsListEpic, { addNewSuccessEpic } from './addNewAssetsListEpic'
import removeAssetsListEpic from './removeAssetsListEpic'
import addAssetToListEpic from './addAssetToListEpic'
import removeAssetFromListEpic from './removeAssetFromListEpic'
import { fetchAssetsEpic, fetchAssetsFromListEpic } from './fetchAssetsEpic'
import chooseAssetsListEpic from './chooseAssetsListEpic'

export default combineEpics(
  handleFollowProject,
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
  // user's assets lists
  addNewAssetsListEpic,
  addNewSuccessEpic,
  removeAssetsListEpic,
  addAssetToListEpic,
  removeAssetFromListEpic,
  // assets
  fetchAssetsEpic,
  fetchAssetsFromListEpic,
  chooseAssetsListEpic
)
