import Raven from 'raven-js'
import gql from 'graphql-tag'
import { Observable } from 'rxjs'
import { showNotification } from './../actions/rootActions'
import { userGQL } from './handleLaunch'
import * as actions from './../actions/types'

const PrivacyGQL = gql`
  mutation updateTermsAndConditions($privacyPolicyAccepted: Boolean!,
  $marketingAccepted: Boolean!
  ) {
    updateTermsAndConditions(privacyPolicyAccepted: $privacyPolicyAccepted,
      marketingAccepted: $marketingAccepted
    ) {
     id,
     privacyPolicyAccepted,
     marketingAccepted
    }
  }
`

const privacyGQLHelper = (user, type) => {
  const marketingAccepted = type === actions.USER_TOGGLE_MARKETING
    ? !user.data.marketingAccepted : user.data.marketingAccepted
  const privacyPolicyAccepted = type === actions.USER_TOGGLE_PRIVACY_POLICY
    ? !user.data.privacyPolicyAccepted : user.data.privacyPolicyAccepted
  return {
    variables: {
      marketingAccepted,
      privacyPolicyAccepted
    },
    optimisticResponse: {
      __typename: 'Mutation',
      updateTermsAndConditions: {
        __typename: 'User',
        id: user.data.id,
        privacyPolicyAccepted,
        marketingAccepted
      }
    },
    update: proxy => {
      let data = proxy.readQuery({ query: userGQL })
      if (type === actions.USER_TOGGLE_PRIVACY_POLICY) {
        data.privacyPolicyAccepted = !data.privacyPolicyAccepted
      }
      if (type === actions.USER_TOGGLE_MARKETING) {
        data.marketingAccepted = !data.marketingAccepted
      }
      proxy.writeQuery({ query: userGQL, data })
    }
  }
}

const handleGDPR = (action$, store, { client }) =>
  action$.ofType(actions.USER_TOGGLE_PRIVACY_POLICY,
    actions.USER_TOGGLE_MARKETING)
    .switchMap(action => {
      const user = store.getState().user
      const mutationPromise = client.mutate({
        mutation: PrivacyGQL,
        ...privacyGQLHelper(user, action.type)
      })
      return Observable.from(mutationPromise)
        .mergeMap(({ data }) => {
          console.log(data.updateTermsAndConditions)
          return Observable.merge(
            Observable.of({
              type: actions.USER_SETTING_GDPR,
              payload: {
                privacyPolicyAccepted: (data.updateTermsAndConditions || {}).privacyPolicyAccepted,
                marketingAccepted: (data.updateTermsAndConditions || {}).marketingAccepted
              }
            }),
            Observable.of(showNotification('Privacy settings is changed'))
          )
        })
        .catch(error => {
          Raven.captureException(error)
          return Observable.of({ type: 'TOGGLE_GDPR_FAILED', payload: error })
        })
    })

export default handleGDPR
