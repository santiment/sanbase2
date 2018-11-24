import React, { PureComponent } from 'react'
import { Label, Icon, Button } from 'semantic-ui-react'
import { Link } from 'react-router-dom'
import { loadKeyState, saveKeyState } from './utils/localStorage'

class HeaderMsg extends PureComponent {
  state = {
    isHidden: loadKeyState('trendsMsg')
  }

  hideMsg = () => {
    this.setState({
      isHidden: true
    })
    saveKeyState('trendsMsg', true)
  }

  render () {
    if (this.state.isHidden) {
      return null
    }
    return (
      <div className='new-status-message'>
        <Link to='/trends' onClick={this.hideMsg}>
          <Label color='green' horizontal>
            NEW
          </Label>
          We prepared for you crypto trends in social media{' '}
          <Icon name='angle right' />
        </Link>
        <Button onClick={this.hideMsg}>Got it!</Button>
      </div>
    )
  }
}

export default HeaderMsg
