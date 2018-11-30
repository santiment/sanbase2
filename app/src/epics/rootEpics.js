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
import createWatchlistEpic, {
  createWatchlistSuccessEpic
} from './createWatchlistEpic'
import addAssetToWatchlistEpic from './addAssetToWatchlistEpic'
import removeWatchlistEpic from './removeWatchlistEpic'
import removeAssetFromWatchlistEpic from './removeAssetFromWatchlistEpic'
import {
  fetchAssetsEpic,
  fetchAssetsFromListEpic,
  fetchAssetsFromSharedListEpic
} from './fetchAssetsEpic'
import fetchTimeseriesEpic from './fetchTimeseriesEpic'
import handleNightModeToggle from './handleNightModeToggle'
import handleBetaModeToggle from './handleBetaModeToggle'
import { fetchHypedTrends } from './../components/Trends/fetchHypedTrends'
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
  apikeyGenerateEpic,
  apikeyRevokeEpic,
  handleNightModeToggle,
  handleBetaModeToggle,
  keyboardEpic,
  // user's assets lists
  createWatchlistEpic,
  createWatchlistSuccessEpic,
  removeWatchlistEpic,
  addAssetToWatchlistEpic,
  removeAssetFromWatchlistEpic,
  // assets
  fetchAssetsEpic,
  fetchAssetsFromListEpic,
  fetchAssetsFromSharedListEpic,
  // timeseries
  fetchTimeseriesEpic,
  // trends
  fetchHypedTrends
)
