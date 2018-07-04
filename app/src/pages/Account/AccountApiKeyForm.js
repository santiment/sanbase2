import React, { Fragment } from 'react'
import { Divider } from 'semantic-ui-react'
import { Button } from 'glamorous';

/*
  TODO:
  1. Generate api key button.
    a) Wait for response and populate store/field
  2. API Key form
    a) Api key should not be visible by default
    b) Click on a [Reveal] button to see it
  3. [Revoke] button ?
*/

const AccountApiKeyForm = ({ apikeys }) => {
  return (
    <Fragment>
      <h3>API Key</h3>
      <Divider />
      <div className='api-key'>
        <p>Here will be your API key</p>
        {apikeys.length === 0
          ? <button type='button' >Generate API Key</button>
          : apikeys.map(apiKey => `Your api key is: ${apiKey}`)}
      </div>
    </Fragment>
  )
}

export default AccountApiKeyForm
