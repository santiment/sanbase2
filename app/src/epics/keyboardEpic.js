import { Observable } from 'rxjs'
import { APP_TOGGLE_SEARCH_FOCUS } from './../actions/types'

const keyboard$ = Observable.fromEvent(window, 'keydown')

const keyboardEpic = (action$, store, { client }) =>
  action$.ofType('[app] LAUNCHED').mergeMap(() =>
    keyboard$
      .filter(({ key }) => {
        const bodyHasFocus = document.activeElement === document.body
        return key === '/' && bodyHasFocus
      })
      .mergeMap(event => {
        return Observable.merge(
          Observable.of({ type: APP_TOGGLE_SEARCH_FOCUS })
        )
      })
  )

export default keyboardEpic
