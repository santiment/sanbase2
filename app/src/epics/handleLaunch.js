import Raven from 'raven-js'
import { ofType } from 'redux-observable'
import { Observable } from 'rxjs'
import { mergeMap } from 'rxjs/operators'
import gql from 'graphql-tag'
import { hasMetamask } from './../web3Helpers'
import * as actions from './../actions/types'

export const userGQL = gql`
  query {
    currentUser {
      id
      email
      username
      sanBalance
      privacyPolicyAccepted
      marketingAccepted
      ethAccounts {
        address
        sanBalance
      }
      apikeys
    }
  }
`

const handleLaunch = (action$, store, { client }) =>
  action$.pipe(
    ofType(actions.APP_LAUNCHED),
    mergeMap(() => {
      const queryPromise = client.query({
        options: { fetchPolicy: 'network-only' },
        query: userGQL
      })
      return Observable.from(queryPromise)
        .map(({ data }) => {
          if (data.currentUser) {
            return {
              type: actions.CHANGE_USER_DATA,
              user: data.currentUser,
              hasMetamask: hasMetamask()
            }
          }
          client.cache.reset()
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
        .takeUntil(action$.ofType(actions.USER_LOGIN_SUCCESS))
    })
  )

export default handleLaunch
