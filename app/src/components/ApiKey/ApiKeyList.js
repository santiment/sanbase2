import React, { Component } from 'react'
import ApiKey from './ApiKey'
import ApiKeyRevokeButton from './ApiKeyRevokeButton'

export class ApiKeyList extends Component {
  render () {
    const {apikeys, dispatchApikeyRevoke} = this.props

    if (!apikeys.length) {
      return 'You don\'t have any api keys for now'
    }

    return (
      <ol>
        {apikeys.map(apikey => <li key={apikey}>
          <ApiKey apikey={apikey} />
          {dispatchApikeyRevoke && <ApiKeyRevokeButton apikey={apikey} dispatchApikeyRevoke={dispatchApikeyRevoke} />}
        </li>)}
      </ol>
    )
  }
}

export default ApiKeyList
