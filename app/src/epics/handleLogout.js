import Raven from 'raven-js'
import { ofType } from 'redux-observable'
import { Observable } from 'rxjs'
import { mergeMap } from 'rxjs/operators'
import * as actions from './../actions/types'

const handleLogout = (action$, store, { client }) =>
  action$.pipe(
    ofType(actions.USER_LOGOUT_SUCCESS),
    mergeMap(() => {
      return Observable.from(client.resetStore())
        .map(({ data }) => {
          return {
            type: actions.APP_USER_HAS_INACTIVE_TOKEN
          }
        })
        .catch(error => {
          Raven.captureException(error)
          client.cache.reset()
          return {
            type: actions.APP_USER_HAS_INACTIVE_TOKEN,
            payload: {
              error
            }
          }
        })
    })
  )

export default handleLogout
