import { Observable } from 'rxjs'
import {
  USER_TOGGLE_BETA_MODE,
  APP_USER_BETA_MODE_SAVE
} from './../actions/types'
import { saveKeyState } from '../utils/localStorage'

const handleBetaModeToggle = (action$, store) =>
  action$
    .ofType(USER_TOGGLE_BETA_MODE)
    .debounceTime(200)
    .map(() => {
      const isBetaModeEnabled = !store.getState().rootUi.isBetaModeEnabled
      saveKeyState('isBetaModeEnabled', isBetaModeEnabled)
      return Observable.of(isBetaModeEnabled)
    })
    .mergeMap(({ value }) =>
      Observable.of({
        type: APP_USER_BETA_MODE_SAVE,
        payload: value
      })
    )

export default handleBetaModeToggle
