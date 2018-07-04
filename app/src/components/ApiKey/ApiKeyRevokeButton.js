import React from 'react'
import { graphql } from 'react-apollo'
import {revokeApikeyGQL} from './apikeyGQL'

const ApiKeyRevokeButton = ({apikey, revokeApikey, dispatchApikeyRevoke}) => {
  return (
    <button type='button' onClick={() =>
      revokeApikey({variables: {apikey}})
    .then(({data: {revokeApikey}}) => {
      // console.log(data, data.revokeApikey)
      dispatchApikeyRevoke(revokeApikey.apikeys)
    }).catch(console.log)} >Revoke this API Key</button>
  )
}

export default graphql(revokeApikeyGQL, { name: 'revokeApikey' })(ApiKeyRevokeButton)
