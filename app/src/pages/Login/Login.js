import React, { Fragment } from 'react'
import {
  compose,
  pure,
  withState
} from 'recompose'
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

export const Login = ({
  currentStep,
  changeStep,
  isDesktop
}) => {
  if (currentStep === STEPS.metamask) {
    return (
      <AuthProvider gotoBack={() => changeStep(STEPS.signin)}>
        <EthLogin />
      </AuthProvider>
    )
  } else if (currentStep === STEPS.email) {
    return (
      <AuthProvider gotoBack={() => changeStep(STEPS.signin)}>
        <EmailLogin />
      </AuthProvider>
    )
  }
  return (
    <ChooseAuthProvider
      gotoMetamask={() => changeStep(STEPS.metamask)}
      gotoEmail={() => changeStep(STEPS.email)}
      isDesktop={isDesktop} />
  )
}

export default compose(
  withState('currentStep', 'changeStep', STEPS.signin),
  pure
)(Login)
