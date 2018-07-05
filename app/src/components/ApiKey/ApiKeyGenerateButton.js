import React from 'react'
import { graphql } from 'react-apollo'
import { Button } from 'semantic-ui-react'
import { generateApikeyGQL } from './apikeyGQL'

const ApiKeyGenerateButton = ({ generateApikey, dispatchApikeyGenerate }) => {
  return (
    <Button
      positive
      onClick={() =>
        generateApikey()
          .then(({ data: { generateApikey } }) =>
            dispatchApikeyGenerate(generateApikey.apikeys)
          )
          .catch(console.log)}
    >
      Generate new API Key
    </Button>
  )
}

export default graphql(generateApikeyGQL, { name: 'generateApikey' })(
  ApiKeyGenerateButton
)
