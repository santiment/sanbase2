import React, { Fragment } from 'react'
import {
  compose,
  pure,
  withState
} from 'recompose'
import { Button, Icon } from 'semantic-ui-react'
import metamaskIcon from '../../assets/metamask-icon-64.png'
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
      <Button onClick={gotoBack} basic >
        All login options
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
    <h1>
      Welcome to Sanbase
    </h1>
    <p>
      By having a Sanbase account, you can see more data and insights about crypto projects.
      You can vote and comment on all your favorite insights and more.
    </p>
    <div className='login-actions'>
      {isDesktop &&
      <Button
        onClick={gotoMetamask}
        basic
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
          width={32}
          height={32} />
        Sign in with Metamask
      </Button>}
      <Button
        onClick={gotoEmail}
        basic
        className='sign-in-btn'
      >
        <Icon size='large' name='mail outline' />
        <span>Sign in with email</span>
      </Button>
    </div>
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
