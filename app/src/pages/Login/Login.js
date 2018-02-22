import React, { Fragment } from 'react'
import {
  compose,
  pure,
  withState
} from 'recompose'
import GoogleAnalytics from 'react-ga'
import { Button, Icon } from 'semantic-ui-react'
import metamaskIcon from '../../assets/metamask-icon-64-2.png'
import EmailLogin from './EmailLogin'
import EthLogin from './EthLogin'
import './Login.css'

const STEPS = {
  signin: 'signin',
  email: 'email',
  metamask: 'metamask'
}

const AuthProvider = ({children, gotoBack}) => {
  return (
    <Fragment>
      <h2>Authenticate</h2>
      {children}
      <Button
        className='auth-goto-back-button'
        onClick={gotoBack} basic >
        <Icon name='long arrow left' /> All login options
      </Button>
    </Fragment>
  )
}

const ChooseAuthProvider = ({
  isDesktop,
  gotoEmail,
  gotoMetamask
}) => (
  <Fragment>
    <h2>
      Welcome to Sanbase
    </h2>
    <div className='login-actions'>
      {isDesktop &&
      <Button
        onClick={gotoMetamask}
        basic
        className='metamask-btn'
        style={{
          display: 'flex',
          alignItems: 'center',
          paddingTop: '5px',
          paddingBottom: '5px'
        }}
      >
        <img
          src={metamaskIcon}
          alt='metamask logo'
          width={28}
          height={28} />&nbsp;
        Login with Metamask
      </Button>}
      <Button
        onClick={gotoEmail}
        basic
        className='sign-in-btn'
      >
        <Icon size='large' name='mail outline' />&nbsp;
        <span>Login with email</span>
      </Button>
    </div>
    <p><strong>Why Log In?</strong><br />
      <Icon name='signal' style={{color: '#bbb'}} /> See more crypto data and insights.<br />
      <Icon name='heart empty' style={{color: '#bbb'}} /> Vote on all your favorite insights and more.
    </p>
  </Fragment>
)

const gotoBack = changeStep => {
  GoogleAnalytics.event({
    category: 'User',
    action: 'Goto list of auth options'
  })
  changeStep(STEPS.signin)
}

export const Login = ({
  currentStep,
  changeStep,
  isDesktop
}) => {
  if (currentStep === STEPS.metamask) {
    return (
      <AuthProvider gotoBack={() => gotoBack(changeStep)}>
        <EthLogin />
      </AuthProvider>
    )
  } else if (currentStep === STEPS.email) {
    return (
      <AuthProvider gotoBack={() => gotoBack(changeStep)}>
        <EmailLogin />
      </AuthProvider>
    )
  }
  return (
    <ChooseAuthProvider
      gotoMetamask={() => {
        GoogleAnalytics.event({
          category: 'User',
          action: 'Choose an metamask provider'
        })
        changeStep(STEPS.metamask)
      }}
      gotoEmail={() => {
        GoogleAnalytics.event({
          category: 'User',
          action: 'Choose an email provider'
        })
        changeStep(STEPS.email)
      }}
      isDesktop={isDesktop} />
  )
}

export default compose(
  withState('currentStep', 'changeStep', STEPS.signin),
  pure
)(Login)
