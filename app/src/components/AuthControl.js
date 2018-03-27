import React, { Fragment } from 'react'
import {
  Button,
  Popup,
  Icon
} from 'semantic-ui-react'
import Balance from './../components/Balance'
import './AuthControl.css'

const AccountLinks = ({
  logout,
  openSettings,
  username,
  handleNavigation,
  isDesktop
}) => (
  <div className='acct-links'>
    {username && !isDesktop &&
    <div className='account-name'>
      {username}
    </div>}
    <Button basic={isDesktop} onClick={openSettings}>Settings</Button>
    {isDesktop &&
      <Fragment>
        <Button basic={isDesktop} onClick={() => handleNavigation('roadmap')}>
          Roadmap
        </Button>
      </Fragment>}
    <hr />
    <Button
      className='logoutBtn'
      color='orange'
      basic={isDesktop}
      onClick={logout}>
      Logout
    </Button>
  </div>
)

const AuthControl = ({
  user,
  login,
  logout,
  openSettings,
  handleNavigation,
  isDesktop = true
}) => {
  if (user.username && isDesktop) {
    return (
      <div className='user-auth-control'>
        <Popup basic wide trigger={
          <Icon
            style={{color: 'white', pointer: 'cursor'}}
            size='large'
            name='user circle' />
        } on='click'>
          <AccountLinks
            isDesktop={isDesktop}
            username={user.username}
            handleNavigation={handleNavigation}
            openSettings={openSettings}
            logout={logout} />
        </Popup>
      </div>
    )
  }
  if (user.username && !isDesktop) {
    return (
      <div className='user-auth-control'>
        <div className='acct'>
          <Balance user={user} />
        </div>
        <AccountLinks
          openSettings={openSettings}
          logout={logout} />
      </div>
    )
  }
  return (
    <div className='user-auth-control'>
      <Button
        onClick={login}>
        Login
      </Button>
    </div>
  )
}

export default AuthControl
