import React, { Component } from 'react'
import ApiKey from './ApiKey'
import ApiKeyRevokeButton from './ApiKeyRevokeButton'
import { Map } from 'core-js'

export class ApiKeyList extends Component {
  // eslint-disable-next-line
  state = {
    isHidden: new Map(this.props.apikeys.map(apikey => [apikey, true]))
  }
  // eslint-disable-next-line
  onVisibilityButtonClick = (apikey) => {
    this.setState(prevState => {
      const {isHidden} = prevState
      return ({
        isHidden: new Map(isHidden).set(apikey, !isHidden.get(apikey))
      })
    })
  }

  render () {
    const {isHidden} = this.state
    const {apikeys, dispatchApikeyRevoke} = this.props

    if (!apikeys.length) {
      return 'You don\'t have any api keys for now'
    }

    return (
      <ol>
        {apikeys.map(apikey => <li key={apikey}>
          <ApiKey apikey={apikey} isHidden={isHidden.get(apikey)} onVisibilityButtonClick={this.onVisibilityButtonClick} />
          {dispatchApikeyRevoke && <ApiKeyRevokeButton apikey={apikey} dispatchApikeyRevoke={dispatchApikeyRevoke} />}
        </li>)}
      </ol>
    )
  }
}

export default ApiKeyList
