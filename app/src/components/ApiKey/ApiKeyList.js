import React, { Component } from 'react'
import ApiKey from './ApiKey'

export class ApiKeyList extends Component {
  render () {
    const {apikeys} = this.props

    if (!apikeys.length) {
      return 'You don\'t have any api keys for now'
    }

    return (
      <ol>
        {apikeys.map(apikey => <ApiKey key={apikey} apikey={apikey} />)}
      </ol>
    )
  }
}

export default ApiKeyList
