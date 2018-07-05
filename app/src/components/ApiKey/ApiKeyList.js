import React, { Component } from 'react'
import ApiKey from './ApiKey'
import ApiKeyRevokeButton from './ApiKeyRevokeButton'
import './ApiKeyList.css'

export class ApiKeyList extends Component {
  // eslint-disable-next-line
  state = {
    isHidden: new Map(this.props.apikeys.map(apikey => [apikey, true]))
  }
  componentWillReceiveProps ({ apikeys }) {
    const { isHidden } = this.state
    if (apikeys.length !== isHidden.size) {
      this.setState({
        isHidden: new Map(
          apikeys.map(apikey => {
            const isPreviouslyHidden = isHidden.get(apikey)
            return [
              apikey,
              isPreviouslyHidden !== undefined ? isPreviouslyHidden : true
            ]
          })
        )
      })
    }
  }
  // eslint-disable-next-line
  onVisibilityButtonClick = apikey => {
    this.setState(prevState => {
      const { isHidden } = prevState
      return {
        isHidden: new Map(isHidden).set(apikey, !isHidden.get(apikey))
      }
    })
  }

  render () {
    const { isHidden } = this.state
    const { apikeys, dispatchApikeyRevoke } = this.props

    return (
      <ol className='ApiKeyList'>
        {apikeys.map(apikey => (
          <li className='ApiKeyList__item' key={apikey}>
            <ApiKey
              apikey={apikey}
              isHidden={isHidden.get(apikey)}
              onVisibilityButtonClick={this.onVisibilityButtonClick}
            />
            {dispatchApikeyRevoke &&
              <ApiKeyRevokeButton
                apikey={apikey}
                dispatchApikeyRevoke={dispatchApikeyRevoke}
              />}
          </li>
        ))}
      </ol>
    )
  }
}

export default ApiKeyList
