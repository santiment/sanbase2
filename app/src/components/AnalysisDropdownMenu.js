import React from 'react'
import { Popup, Icon } from 'semantic-ui-react'
import { Link } from 'react-router-dom'
import './AnalysisDropdownMenu.css'

export const AnalysisDropdownMenu = () => (
  <Popup
    mouseLeaveDelay={2000}
    basic
    content={
      <div className='app-menu-popup'>
        <Link
          className='app-menu__page-link'
          to={'/insights'}>
          <Icon name='world' />
          Insights
        </Link>
        <Link
          className='app-menu__page-link'
          to={'/signals'}>
          <Icon name='fork' />
          Signals
        </Link>
      </div>
    }
    trigger={
      <span className='app-menu__page-link'>
        Analysis
      </span>
    }
    position='bottom center'
    on='hover'
  />
)

export default AnalysisDropdownMenu
