import React, { Fragment } from 'react'
import { Divider } from 'semantic-ui-react'
import ApiKeyGenerateButton from '../../components/ApiKey/ApiKeyGenerateButton'
import ApiKeyList from '../../components/ApiKey/ApiKeyList'

const AccountApiKeyForm = ({ apikeys, dispatchApikeysGenerate, dispatchApikeyRevoke }) => {
  return (
    <Fragment>
      <h3>API Keys</h3>
      <Divider />
      <div className='api-key'>
        <ApiKeyGenerateButton dispatchApikeysGenerate={dispatchApikeysGenerate} />
        <ApiKeyList apikeys={apikeys} dispatchApikeyRevoke={dispatchApikeyRevoke} />
      </div>
    </Fragment>
  )
}

export default AccountApiKeyForm
