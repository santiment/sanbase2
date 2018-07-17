import { Observable } from 'rxjs'
import {
  USER_TOGGLE_COLOR_MODE,
  APP_USER_COLOR_MODE_SAVE
} from './../actions/types'

const handleColorModeChange = action$ =>
  action$
    .ofType(USER_TOGGLE_COLOR_MODE)
    .switchMap(() =>
      Observable.of(document.body.classList.toggle('night-mode'))
    )
    .debounceTime(1000)
    .mergeMap(isNightModeEnabled =>
      Observable.of({
        type: APP_USER_COLOR_MODE_SAVE,
        payload: isNightModeEnabled
      })
    )

export default handleColorModeChange
