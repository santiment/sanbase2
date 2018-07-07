import Raven from 'raven-js'
import { Observable } from 'rxjs'
import gql from 'graphql-tag'
import {
  USER_APIKEY_REVOKE,
  USER_APIKEY_REVOKE_SUCCESS
} from './../actions/types'

const revokeApikeyGQL = gql`
  mutation revokeApikey($apikey: String!) {
    revokeApikey(apikey: $apikey) {
      apikeys
    }
  }
`

const handleApikeyRevoke = (action$, store, { client }) =>
  action$.ofType(USER_APIKEY_REVOKE).switchMap(({apikey}) => {
    const mutation = client.mutate({
      mutation: revokeApikeyGQL,
      variables: {
        apikey
      }
    })
    return Observable.from(mutation)
      .mergeMap(({ data: { revokeApikey } }) =>
        Observable.of({
          type: USER_APIKEY_REVOKE_SUCCESS,
          apikeys: revokeApikey.apikeys
        })
      )
      .catch(error => {
        Raven.captureException(error)
        return Observable.of({
          type: 'USER_APIKEY_REVOKE_FAIL',
          payload: error
        })
      })
  })

export default handleApikeyRevoke
