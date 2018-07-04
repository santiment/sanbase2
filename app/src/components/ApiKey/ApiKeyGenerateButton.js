import React from 'react'
import { graphql } from 'react-apollo'
import {generateApikeyGQL} from './apikeyGQL'

const ApiKeyGenerateButton = ({generateApikey, dispatchApikeysGenerate}) => {
  return (
    <button type='button' onClick={() => generateApikey().then(({data: {generateApikey}}) => {
      dispatchApikeysGenerate(generateApikey.apikeys)
    }).catch(console.log)} >Generate API Key</button>
  )
}

export default graphql(generateApikeyGQL, { name: 'generateApikey' })(ApiKeyGenerateButton)
