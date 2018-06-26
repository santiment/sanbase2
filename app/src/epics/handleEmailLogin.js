import Raven from 'raven-js'
import GoogleAnalytics from 'react-ga'
import { Observable } from 'rxjs'
import gql from 'graphql-tag'
import { replace } from 'react-router-redux'
import { showNotification } from './../actions/rootActions'
import * as actions from './../actions/types'
import { savePrevAuthProvider } from './../utils/localStorage'

const emailLoginVerifyGQL = gql`
  mutation emailLoginVerify($email: String!, $token: String!) {
    emailLoginVerify(
      email: $email,
      token: $token
    ) {
      token
      user {
        id,
        email,
        username,
        privacyPolicyAccepted,
        marketingAccepted,
        consent_id,
        sanBalance,
        ethAccounts {
          address,
          sanBalance
        }
      }
    }
  }
`

export const handleLoginSuccess = (action$, store, { client }) =>
  action$.ofType(actions.USER_LOGIN_SUCCESS)
    .switchMap(action => {
      return Observable.from(client.resetStore())
        .mergeMap(() => {
          const { user, token, consent } = action
          return Observable.merge(
            Observable.of(showNotification('You are logged in!')),
            Observable.of(
              consent
                ? window.location.replace(`/consent?consent=${user.consent_id}&token=${token}`)
                : replace('/')
            )
          )
        })
        .catch(error => {
          return Observable.of({ type: actions.USER_LOGIN_FAILED, payload: error })
        })
    })

const handleEmailLogin = (action$, store, { client }) =>
  action$.ofType(actions.USER_EMAIL_LOGIN)
    .switchMap(action => {
      const mutation = client.mutate({
        mutation: emailLoginVerifyGQL,
        variables: action.payload
      })
      return Observable.from(mutation)
        .mergeMap(({data}) => {
          const { token, user } = data.emailLoginVerify
          GoogleAnalytics.event({
            category: 'User',
            action: 'Success login with email'
          })
          savePrevAuthProvider('email')
          return Observable.of({
            type: actions.USER_LOGIN_SUCCESS,
            token,
            user,
            consent: user.consent_id
          })
        })
        .catch(error => {
          Raven.captureException(error)
          GoogleAnalytics.event({
            category: 'User',
            action: 'Failed login with email'
          })
          return Observable.of({ type: actions.USER_LOGIN_FAILED, payload: error })
        })
    })

export default handleEmailLogin
