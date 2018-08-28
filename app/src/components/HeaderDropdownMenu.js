import React from 'react'
import { Button, Divider, Icon } from 'semantic-ui-react'
import { NavLink, Link } from 'react-router-dom'
import FeedbackBtn from './FeedbackBtn'
import SmoothDropdownItem from './SmoothDropdown/SmoothDropdownItem'
import './HeaderDropdownMenu.css'

const HeaderDesktopDropMenu = ({ isLoggedin, logout }) => {
  if (isLoggedin) {
    return (
      <div className='user-auth-control'>
        <FeedbackBtn />
        <SmoothDropdownItem
          trigger={<Button circular icon='user' />}
          id='profile'
        >
          <div className='app-menu-popup'>
            <Link className='app-menu__page-link' to={'/roadmap'}>
              <Icon name='map' />
              Roadmap
            </Link>
            <Link className='app-menu__page-link' to={'/account'}>
              <Icon name='setting' />
              Account Settings
            </Link>
            <Divider />
            <Button className='logoutBtn' color='orange' basic onClick={logout}>
              Logout
            </Button>
          </div>
        </SmoothDropdownItem>
      </div>
    )
  }
  return (
    <div className='user-auth-control'>
      <FeedbackBtn />
      <NavLink to={'/login'}>Login</NavLink>
    </div>
  )
}

export default HeaderDesktopDropMenu
