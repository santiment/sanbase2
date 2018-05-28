import React from 'react'
import { Button, Popup, Icon } from 'semantic-ui-react'
import { NavLink as Link } from 'react-router-dom'
import FeedbackBtn from './FeedbackBtn'
import './AuthControl.css'

const HeaderDesktopDropMenu = ({
  isLoggedin,
  logout,
  handleNavigation
}) => {
  if (isLoggedin) {
    return (
      <div className='user-auth-control'>
        <FeedbackBtn />
        <Popup basic wide trigger={
          <Icon
            style={{color: 'white', pointer: 'cursor'}}
            size='large'
            name='user circle' />
        } on='click'>
          <div className='acct-links'>
            <Button basic onClick={() => handleNavigation('account')}>Settings</Button>
            <hr />
            <Button
              className='logoutBtn'
              color='orange'
              basic
              onClick={logout}>
              Logout
            </Button>
          </div>
        </Popup>
      </div>
    )
  }
  return (
    <div className='user-auth-control'>
      <Link to={'/login'}>
        Login
      </Link>
    </div>
  )
}

export default HeaderDesktopDropMenu
