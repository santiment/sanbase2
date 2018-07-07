import React from 'react'
import { Button } from 'semantic-ui-react'

const ApiKeyRevokeButton = ({ apikey, revokeAPIKey, onRevokeButtonClick }) => {
  return (
    <Button
      negative
      onClick={() => {
        revokeAPIKey(apikey)
        onRevokeButtonClick(apikey)
      }}
    >
      Revoke
    </Button>
  )
}

export default ApiKeyRevokeButton
