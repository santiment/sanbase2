import React from 'react'
import { Label } from 'semantic-ui-react'

const Status = () => {
  return (
    <div style={{
      marginTop: '1em',
      display: 'flex',
      justifyContent: 'center'
    }}>
      <h1>
        <Label size='massive' color='green' horizontal>All System Operational!</Label>
      </h1>
    </div>
  )
}

export default Status
