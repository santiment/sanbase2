import 'rxjs'
import { combineEpics } from 'redux-observable'
import handleOffline from './handleOffline'
import handleLauched from './handleLaunch'
import handleLogout from './handleLogout'
import handleEmailLogin, { handleLoginSuccess } from './handleEmailLogin'
import handleEthLogin from './handleEthLogin'
import handleGDPR from './handleGDPR'
import handleRouter from './handleRouter'
import apikeyGenerateEpic from './apikeyGenerateEpic'
import apikeyRevokeEpic from './apikeyRevokeEpic'
import addNewAssetsListEpic, { addNewSuccessEpic } from './addNewAssetsListEpic'
import removeAssetsListEpic from './removeAssetsListEpic'
import addAssetToListEpic from './addAssetToListEpic'
import removeAssetFromListEpic from './removeAssetFromListEpic'
import { fetchAssetsEpic, fetchAssetsFromListEpic } from './fetchAssetsEpic'

export default combineEpics(
  handleOffline,
  handleLauched,
  handleLogout,
  handleEmailLogin,
  handleLoginSuccess,
  handleEthLogin,
  handleGDPR,
  handleRouter,
  apikeyGenerateEpic,
  apikeyRevokeEpic,
  // user's assets lists
  addNewAssetsListEpic,
  addNewSuccessEpic,
  removeAssetsListEpic,
  addAssetToListEpic,
  removeAssetFromListEpic,
  // assets
  fetchAssetsEpic,
  fetchAssetsFromListEpic
)
