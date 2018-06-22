import Raven from 'raven-js'
import { ofType } from 'redux-observable'
import { switchMap } from 'rxjs/operators'
import gql from 'graphql-tag'
import { hasMetamask } from './../web3Helpers'
import * as actions from './../actions/types'

export const userGQL = gql`
  query {
    currentUser {
      id,
      email,
      username,
      privacyPolicyAccepted,
      marketingAccepted,
      ethAccounts{
        address,
        sanBalance
      }
    }
  }
`

const handleLaunch = (action$, store, { client }) =>
  action$.pipe(
    ofType(actions.APP_LAUNCHED),
    switchMap(() => {
      return client.query({
        options: { fetchPolicy: 'network-only' },
        query: userGQL
      })
      .then(response => {
        if (response.data.currentUser) {
          return {
            type: actions.CHANGE_USER_DATA,
            user: response.data.currentUser,
            hasMetamask: hasMetamask()
          }
        }
        client.resetStore()
        return {
          type: actions.APP_USER_HAS_INACTIVE_TOKEN
        }
      })
      .catch(error => {
        Raven.captureException(error)
        client.resetStore()
        return {
          type: actions.APP_USER_HAS_INACTIVE_TOKEN,
          payload: {
            error
          }
        }
      })
    })
  )

export default handleLaunch
