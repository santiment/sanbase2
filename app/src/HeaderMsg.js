import React, { PureComponent } from 'react'
import { Label, Icon, Button } from 'semantic-ui-react'
import { Link } from 'react-router-dom'
import { saveKeyState } from './utils/localStorage'

class HeaderMsg extends PureComponent {
  state = {
    isShown: true
  }

  hideMsg = () => {
    this.setState({
      isShown: false
    })
    saveKeyState('trendsMsg', true)
  }

  render () {
    return (
      this.state.isShown && (
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
    )
  }
}

export default HeaderMsg
