import React from 'react'
import { Button } from 'semantic-ui-react'

const ApiKeyGenerateButton = ({ generateAPIKey }) => {
  return (
    <Button
      positive
      onClick={generateAPIKey}
    >
      Generate new API Key
    </Button>
  )
}

export default ApiKeyGenerateButton
