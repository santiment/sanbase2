import React, { Fragment } from 'react'
import { Divider } from 'semantic-ui-react'
import ApiKeyGenerateButton from '../../components/ApiKey/ApiKeyGenerateButton'

const AccountApiKeyForm = ({ apikeys, dispatchApikeysGenerate }) => {
  return (
    <Fragment>
      <h3>API Key</h3>
      <Divider />
      <div className='api-key'>
        <p>Here will be your API key</p>
        <ApiKeyGenerateButton dispatchApikeysGenerate={dispatchApikeysGenerate} />
        {apikeys.length === 0
          ? 'At this moment you don\'t have any api keys'
          : apikeys.map(apiKey => `Your api key is: ${apiKey}`)}
      </div>
    </Fragment>
  )
}

export default AccountApiKeyForm
