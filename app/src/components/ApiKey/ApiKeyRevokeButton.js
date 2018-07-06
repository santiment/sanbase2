import React from 'react'
import { Button } from 'semantic-ui-react'

const ApiKeyRevokeButton = ({ apikey, dispatchApikeyRevoke, onRevokeButtonClick }) => {
  return (
    <Button
      negative
      onClick={() => {
        dispatchApikeyRevoke(apikey)
        onRevokeButtonClick(apikey)
      }}
    >
      Revoke
    </Button>
  )
}

export default ApiKeyRevokeButton
