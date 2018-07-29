import { Observable } from 'rxjs'
import { APP_TOGGLE_SEARCH_FOCUS } from './../actions/types'

const keyboard$ = Observable.fromEvent(window, 'keydown')

// const bodyHasFocus = document.activeElement === document.body
// const hasModifier = e.altKey || e.ctrlKey || e.metaKey
const keyboardEpic = (action$, store, { client }) =>
  action$.ofType('[app] LAUNCHED').mergeMap(() =>
    keyboard$.filter(({ key }) => key === '/').mergeMap(event => {
      return Observable.merge(Observable.of({ type: APP_TOGGLE_SEARCH_FOCUS }))
    })
  )

export default keyboardEpic
