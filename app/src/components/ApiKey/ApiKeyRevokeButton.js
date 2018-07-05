import React from 'react'
import { graphql } from 'react-apollo'
import { Button } from 'semantic-ui-react'
import { revokeApikeyGQL } from './apikeyGQL'

const ApiKeyRevokeButton = ({ apikey, revokeApikey, dispatchApikeyRevoke }) => {
  return (
    <Button
      negative
      onClick={() =>
        revokeApikey({ variables: { apikey } })
          .then(({ data: { revokeApikey } }) =>
            dispatchApikeyRevoke(revokeApikey.apikeys)
          )
          .catch(console.log)}
    >
      Revoke
    </Button>
  )
}

export default graphql(revokeApikeyGQL, { name: 'revokeApikey' })(
  ApiKeyRevokeButton
)
