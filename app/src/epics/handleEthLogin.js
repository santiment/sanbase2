import Raven from 'raven-js'
import GoogleAnalytics from 'react-ga'
import { Observable } from 'rxjs'
import gql from 'graphql-tag'
import { signMessage } from './../web3Helpers'
import * as actions from './../actions/types'
import { savePrevAuthProvider } from './../utils/localStorage'

const ethLoginGQL = gql`
  mutation ethLogin($signature: String!, $address: String!, $messageHash: String!) {
    ethLogin(
      signature: $signature,
      address: $address,
      messageHash: $messageHash) {
        token,
        user {
          id,
          email,
          username,
          privacyPolicyAccepted,
          marketingAccepted,
          ethAccounts {
            address,
            sanBalance
          }
        }
      }
}`

const loginWithEthereum = (address, client) => {
  return new Promise((resolve, reject) => {
    signMessage(address).then(({messageHash, signature}) => {
      const mutation = client.mutate({
        mutation: ethLoginGQL,
        variables: {
          signature,
          address,
          messageHash
        }
      })
      resolve(mutation)
    }).catch(error => {
      reject(error)
    })
  })
}

const handleEthLogin = (action$, store, { client }) =>
  action$.ofType(actions.USER_ETH_LOGIN)
    .switchMap(action => {
      const { address, consent } = action.payload
      return Observable.from(loginWithEthereum(address, client))
        .mergeMap(({ data }) => {
          const { token, user } = data.ethLogin
          savePrevAuthProvider('metamask')
          GoogleAnalytics.event({
            category: 'User',
            action: 'Success login with metamask'
          })
          return Observable.of({
            type: actions.USER_LOGIN_SUCCESS,
            token,
            user,
            consent: user.consent_id || consent
          })
        }).catch(error => {
          Raven.captureException(error)
          GoogleAnalytics.event({
            category: 'User',
            action: 'Failed login with metamask'
          })
          return Observable.of({
            type: actions.USER_LOGIN_FAILED,
            payload: error
          })
        })
    })

export default handleEthLogin
