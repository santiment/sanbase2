import React from 'react'
import { Button, Popup } from 'semantic-ui-react'
import { NavLink as Link } from 'react-router-dom'
import FeedbackBtn from './FeedbackBtn'
import './HeaderDropdownMenu.css'

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
          <Button circular icon='user' />
        } on='click'>
          <div className='dropdown-menu'>
            <Button basic onClick={() => handleNavigation('account')}>
              Settings
            </Button>
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
