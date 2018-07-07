import React from 'react'
import { Button } from 'semantic-ui-react'

const ApiKeyGenerateButton = ({ dispatchApikeyGenerate }) => {
  return (
    <Button
      positive
      onClick={dispatchApikeyGenerate}
    >
      Generate new API Key
    </Button>
  )
}

export default ApiKeyGenerateButton
