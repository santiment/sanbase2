import React from 'react'
import { Button, Popup, Divider } from 'semantic-ui-react'
import { NavLink, Link } from 'react-router-dom'
import FeedbackBtn from './FeedbackBtn'
import './HeaderDropdownMenu.css'

const HeaderDesktopDropMenu = ({
  isLoggedin,
  logout
}) => {
  if (isLoggedin) {
    return (
      <div className='user-auth-control'>
        <FeedbackBtn />
        <Popup basic wide trigger={
          <Button circular icon='user' />
        } on='click'>
          <div className='dropdown-menu'>
            <Link
              className='ui basic button'
              to={'/roadmap'}>
              Roadmap
            </Link>
            <Divider />
            <Link
              className='ui basic button'
              to={'/account'}>
              Account Settings
            </Link>
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
      <NavLink to={'/login'}>
        Login
      </NavLink>
    </div>
  )
}

export default HeaderDesktopDropMenu
