import React from 'react'
import { Popup, Icon } from 'semantic-ui-react'
import { Link } from 'react-router-dom'
import SmoothDDItem from './SmoothDropdown/SmoothDDItem'
import './AnalysisDropdownMenu.css'

export const AnalysisDropdownMenu = () => (
  // <Popup
  <SmoothDDItem
    mouseLeaveDelay={2000}
    basic
    trigger={<span className='app-menu__page-link'>Analysis</span>}
    position='bottom center'
    on='hover'
    id='analysis'
  >
    <div className='app-menu-popup'>
      <Link className='app-menu__page-link' to={'/insights'}>
        <Icon name='world' />
        Insights
      </Link>
      <Link className='app-menu__page-link' to={'/signals'}>
        <Icon name='fork' />
        Signals
      </Link>
    </div>
  </SmoothDDItem>
)

export default AnalysisDropdownMenu
