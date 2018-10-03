import React from 'react'
import SmoothDropdownItem from './../SmoothDropdown/SmoothDropdownItem'
import DesktopAnalysisMenu from './DesktopAnalysisMenu'
import './AnalysisDropdownMenu.css'

export const AnalysisDropdownMenu = () => (
  <SmoothDropdownItem
    trigger={<span className='app-menu__page-link'>Analysis</span>}
    id='analysis'
  >
    <DesktopAnalysisMenu />
  </SmoothDropdownItem>
)

export default AnalysisDropdownMenu
