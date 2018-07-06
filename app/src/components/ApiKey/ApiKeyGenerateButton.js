import React from 'react'
import { Button } from 'semantic-ui-react'
import debounce from 'lodash.debounce'

const ApiKeyGenerateButton = ({ dispatchApikeyGenerate }) => {
  return (
    <Button
      positive
      onClick={debounce(dispatchApikeyGenerate, 200)}
    >
      Generate new API Key
    </Button>
  )
}

export default ApiKeyGenerateButton
