import { Observable } from 'rxjs'
import {
  USER_TOGGLE_NIGHT_MODE,
  APP_USER_NIGHT_MODE_SAVE
} from './../actions/types'
import { saveKeyState } from '../utils/localStorage'

const handleNightModeToggle = action$ =>
  action$
    .ofType(USER_TOGGLE_NIGHT_MODE)
    .exhaustMap(() =>
      Observable.of(document.body.classList.toggle('night-mode'))
    )
    .debounceTime(1000)
    .map(isNightModeEnabled => {
      saveKeyState('isNightModeEnabled', isNightModeEnabled)
      return Observable.of(isNightModeEnabled)
    })
    .mergeMap(({value}) =>
      Observable.of({
        type: APP_USER_NIGHT_MODE_SAVE,
        payload: value
      })
    )

export default handleNightModeToggle
