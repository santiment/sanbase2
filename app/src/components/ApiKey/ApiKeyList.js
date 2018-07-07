import React, { Component } from 'react'
import ApiKey from './ApiKey'
import ApiKeyRevokeButton from './ApiKeyRevokeButton'
import './ApiKeyList.css'

export class ApiKeyList extends Component {
  // eslint-disable-next-line
  state = {
    visibleKeys: new Set()
  }

  // eslint-disable-next-line
  onRevokeButtonClick = apikey => {
    const { visibleKeys } = this.state
    if (!visibleKeys.has(apikey)) return

    const newVisibleKeys = new Set(visibleKeys)
    newVisibleKeys.delete(apikey)
    this.setState({
      visibleKeys: newVisibleKeys
    })
  }

  // eslint-disable-next-line
  onVisibilityButtonClick = apikey => {
    this.setState(prevState => {
      const { visibleKeys } = prevState
      const newVisibleKeys = new Set(visibleKeys)

      if (newVisibleKeys.has(apikey)) {
        newVisibleKeys.delete(apikey)
      } else {
        newVisibleKeys.add(apikey)
      }

      return {
        visibleKeys: newVisibleKeys
      }
    })
  }

  render () {
    const { visibleKeys } = this.state
    const { apikeys, revokeAPIKey } = this.props

    return (
      <ol className='ApiKeyList'>
        {apikeys.map(apikey => (
          <li className='ApiKeyList__item' key={apikey}>
            <ApiKey
              apikey={apikey}
              isVisible={visibleKeys.has(apikey)}
              onVisibilityButtonClick={this.onVisibilityButtonClick}
            />
            {revokeAPIKey &&
              <ApiKeyRevokeButton
                apikey={apikey}
                revokeAPIKey={revokeAPIKey}
                onRevokeButtonClick={this.onRevokeButtonClick}
              />}
          </li>
        ))}
      </ol>
    )
  }
}

export default ApiKeyList
