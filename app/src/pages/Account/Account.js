import React, { Component } from 'react'
import { connect } from 'react-redux'
import { Message } from 'semantic-ui-react'
import { Redirect } from 'react-router-dom'
import AccountHeader from './AccountHeader'
import AccountEmailForm from './AccountEmailForm'
import AccountUsernameForm from './AccountUsernameForm'
import AccountEthKeyForm from './AccountEthKeyForm'
import AccountWallets from './AccountWallets'
import AccountApiKeyForm from './AccountApiKeyForm'
import AccountSessions from './AccountSessions'
import { USER_LOGOUT_SUCCESS, USER_USERNAME_CHANGE, USER_EMAIL_CHANGE, USER_APIKEY_GENERATE, USER_APIKEY_REVOKE } from '../../actions/types'
import './Account.css'
const validate = require('validate.js')

const validateFields = (email, username) => {
  var constraints = {
    email: {
      email: true
    },
    username: {
      length: { minimum: 3 }
    }
  }
  return validate({ email, username }, constraints)
}

const errorValidator = ({ email, username }) => {
  const validation = validateFields(email, username)
  return {
    email: validation && validation.email,
    username: validation && validation.username
  }
}

const successValidator = ({ email, username }) => {
  const validation = validateFields(email, username)
  return {
    email: typeof validation === 'undefined' || !validation.email,
    username: typeof validation === 'undefined' || !validation.username
  }
}

class Account extends Component {
  constructor (props) {
    super(props)
    this.state = {
      emailForm: {
        PENDING: false,
        ERROR: false,
        SUCCESS: false
      },
      usernameForm: {
        PENDING: false,
        ERROR: false,
        SUCCESS: false
      }
    }
    this.emailFormKey = 'emailForm'
    this.usernameFormKey = 'usernameForm'
  }

  setFormStatus (form) {
    return (status, value) => {
      this.setState(prevState => {
        const newFormState = { ...prevState[form] }
        newFormState[status] = value
        return {
          ...prevState,
          [form]: newFormState
        }
      })
    }
  }

  render () {
    const { user, loading, logoutUser, changeEmail, changeUsername, generateAPIKey, revokeAPIKey, isLoggedIn } = this.props
    const { emailForm, usernameForm } = this.state

    if (user && !isLoggedIn) {
      return (
        <Redirect
          to={{
            pathname: '/'
          }}
        />
      )
    }

    return (
      <div className='page account'>
        <AccountHeader />
        {!user.email &&
          <Message
            className='account-message account-message__dashboard'
            warning
            header='Email is not added yet!'
            list={[
              'For acces your dashboard from mobile device, you should add email address.'
            ]}
          />}

        {emailForm.SUCCESS &&
          <Message
            className='account-message account-message__email_success'
            positive
            content={`Email was changed to "${user.email || ''}"!`}
          />}
        {emailForm.ERROR &&
          <Message
            className='account-message account-message__email_error'
            negative
            header='Failed to change email!'
            list={['Try again later...']}
          />}
        {usernameForm.SUCCESS &&
          <Message
            className='account-message account-message__username_success'
            positive
            content={`Username was changed to "${user.username || ''}"!`}
          />}
        {usernameForm.ERROR &&
          <Message
            className='account-message account-message__username_error'
            negative
            header='Failed to change username!'
            list={['Try again later...']}
          />}

        <div className='panel'>
          <AccountEmailForm
            user={user}
            changeEmail={changeEmail}
            successValidator={successValidator}
            errorValidator={errorValidator}
            setFormStatus={this.setFormStatus(this.emailFormKey)}
            isEmailPending={emailForm.PENDING}
          />
          <AccountUsernameForm
            user={user}
            changeUsername={changeUsername}
            successValidator={successValidator}
            errorValidator={errorValidator}
            setFormStatus={this.setFormStatus(this.usernameFormKey)}
            isUsernamePending={usernameForm.PENDING}
          />
          <br />
          <AccountEthKeyForm ethAccounts={user.ethAccounts} loading={loading} />
          <AccountWallets user={user} />
          <AccountApiKeyForm apikeys={user.apikeys} generateAPIKey={generateAPIKey} revokeAPIKey={revokeAPIKey} />
          <AccountSessions onLogoutBtnClick={logoutUser} />
        </div>
      </div>
    )
  }
}

const mapStateToProps = state => ({
  user: state.user.data,
  loading: state.user.isLoading,
  isLoggedIn: !!state.user.token
})

const mapDispatchToProps = dispatch => ({
  logoutUser: () => dispatch({ type: USER_LOGOUT_SUCCESS }),
  changeEmail: email => dispatch({
    type: USER_EMAIL_CHANGE,
    email
  }),
  changeUsername: username => dispatch({
    type: USER_USERNAME_CHANGE,
    username
  }),
  generateAPIKey: () => dispatch({
    type: USER_APIKEY_GENERATE
  }),
  revokeAPIKey: apikey => dispatch({
    type: USER_APIKEY_REVOKE,
    apikey
  })
})

export const UnwrappedAccount = Account // For tests
export default connect(mapStateToProps, mapDispatchToProps)(Account)
