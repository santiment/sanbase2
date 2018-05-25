import { combineEpics } from 'redux-observable'
import 'rxjs'
import handleFavorites from './handleFavorites'

export default combineEpics(
  handleFavorites
)
