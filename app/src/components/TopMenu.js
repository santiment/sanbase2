import React from 'react'
import { Link } from 'react-router-dom'
import 'font-awesome/css/font-awesome.css'
import { Label } from 'semantic-ui-react'
import logo from '../assets/logo_sanbase.png'
import DesktopRightGroupMenu from './DesktopMenu/DesktopRightGroupMenu.js'
import Search from './Search/SearchContainer'
import AnalysisDropdownMenu from './AnalysisDropdownMenu'
import SmoothDropdown from './SmoothDropdown/SmoothDropdown'
import './AppMenu.css'
import './TopMenu.css'

export const TopMenu = ({
  isLoggedIn,
  logout,
  toggleNightMode,
  isNightModeEnabled
}) => (
  <div className='app-menu'>
    <div className='container'>
      <div className='left'>
        <Link to='/' className='brand'>
          <img src={logo} width='115' height='22' alt='SANbase' />
        </Link>
        <Search />
      </div>
      <SmoothDropdown className='right'>
        <div className='menu-list-top'>
          <Link className='app-menu__page-link' to='/trends'>
            Trends{' '}
            <Label color='green' horizontal>
              new
            </Label>
          </Link>
          <Link className='app-menu__page-link' to='/assets'>
            Assets
          </Link>
          <AnalysisDropdownMenu />
        </div>
        <DesktopRightGroupMenu />
      </SmoothDropdown>
    </div>
  </div>
)

export default TopMenu
