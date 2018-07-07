import Raven from 'raven-js'
import { Observable } from 'rxjs'
import gql from 'graphql-tag'
import {
  USER_APIKEY_GENERATE,
  USER_APIKEY_GENERATE_SUCCESS
} from './../actions/types'

const generateApikeyGQL = gql`
  mutation {
    generateApikey {
      apikeys
    }
  }
`

const handleApikeyGenerate = (action$, store, { client }) =>
  action$.ofType(USER_APIKEY_GENERATE).debounceTime(200).switchMap(() => {
    const mutation = client.mutate({
      mutation: generateApikeyGQL
    })
    return Observable.from(mutation)
      .mergeMap(({ data: { generateApikey } }) =>
        Observable.of({
          type: USER_APIKEY_GENERATE_SUCCESS,
          apikeys: generateApikey.apikeys
        })
      )
      .catch(error => {
        Raven.captureException(error)
        return Observable.of({
          type: 'USER_APIKEY_GENERATE_FAIL',
          payload: error
        })
      })
  })

export default handleApikeyGenerate
