import React from 'react'
import { Link } from 'react-router-dom'
import 'font-awesome/css/font-awesome.css'
import logo from '../assets/logo_sanbase.png'
import Search from './Search/SearchContainer'
import DesktopRightGroupMenu from './DesktopMenu/DesktopRightGroupMenu'
import AnalysisDropdownMenu from './DesktopMenu/AnalysisDropdownMenu'
import DesktopAssetsMenu from './DesktopMenu/DesktopAssetsMenu'
import SmoothDropdown from './SmoothDropdown/SmoothDropdown'
import SmoothDropdownItem from './SmoothDropdown/SmoothDropdownItem'
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
          <SmoothDropdownItem
            trigger={<span className='app-menu__page-link'>Assets</span>}
            id='analysis'
          >
            <DesktopAssetsMenu />
          </SmoothDropdownItem>
          <AnalysisDropdownMenu />
        </div>
        <DesktopRightGroupMenu />
      </SmoothDropdown>
    </div>
  </div>
)

export default TopMenu
