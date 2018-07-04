import React, { Component } from 'react'
import ApiKey from './ApiKey'

export class ApiKeyList extends Component {
  render () {
    const {apikeys} = this.props

    return (
      <ol>
        {apikeys.map(apikey => <ApiKey key={apikey} apikey={apikey} />)}
      </ol>
    )
  }
}

export default ApiKeyList
