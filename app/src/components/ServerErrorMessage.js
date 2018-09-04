import React from 'react'
import { Message } from 'semantic-ui-react'

const AssetsTableErrorMessage = () => (
  <div
    style={{
      display: 'flex',
      alignItems: 'center',
      justifyContent: 'center',
      height: '80vh'
    }}
  >
    <Message warning>
      <Message.Header>
        We're sorry, something has gone wrong on our server.
      </Message.Header>
      <p>Please try again later.</p>
    </Message>
  </div>
)

export default AssetsTableErrorMessage
