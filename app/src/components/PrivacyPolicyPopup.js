import React, { Component } from 'react'
import { Link } from 'react-router-dom'
import { Segment, Button } from 'semantic-ui-react'
import './PrivacyPolicyPopup.css'

const getPrivacyPolicyAcceptance = () => {
  try {
    const serializedState = window.sessionStorage.getItem(
      'isPrivacyPolicyAccepted'
    )
    return serializedState === null ? false : JSON.parse(serializedState)
  } catch (error) {
    return undefined
  }
}

const savePrivacyPolicyAcceptance = () => {
  try {
    const serializedState = JSON.stringify(true)
    window.sessionStorage.setItem('isPrivacyPolicyAccepted', serializedState)
  } catch (error) {
    // Ignore write errors.
  }
}

class PrivacyPolicyPopup extends Component {
  // eslint-disable-next-line
  state = {
    isPrivacyPolicyAccepted: getPrivacyPolicyAcceptance()
  }

  // eslint-disable-next-line
  acceptPrivacyPolicy = () => {
    this.setState({ isPrivacyPolicyAccepted: true })
    savePrivacyPolicyAcceptance()
  }

  render () {
    if (this.props.isLoggedIn || this.state.isPrivacyPolicyAccepted) {
      return null
    }
    return (
      <div className='PrivacyPolicyPopup'>
        <Segment className='PrivacyPolicyPopup__container'>
          <p className='PrivacyPolicyPopup__text'>
            Santiment uses  browser cookies to give you the best possible experience. To make Santiment work, we log user data and share it with processors. To use Santiment, you must agree to our <Link to='/privacy-policy'>"Privacy Policy"</Link>, including cookie policy.
          </p>
          <Button
            positive
            className='PrivacyPolicyPopup__btn'
            onClick={this.acceptPrivacyPolicy}
          >
            I agree.
          </Button>
        </Segment>
      </div>
    )
  }
}

export default PrivacyPolicyPopup
