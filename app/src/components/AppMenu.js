import React, { Fragment } from 'react'
import { Icon } from 'react-fa'
import './AppMenu.css'

const AppMenu = ({handleNavigation, showIcons = false, showInsights = false}) => (
  <Fragment>
    {showInsights &&
    <ul className={showIcons ? 'menu-list user-generated' : 'menu-list-top user-generated'} >
      <li onClick={() => handleNavigation('insights')}>
        {showIcons && <i className='fa fa-newspaper-o' />}
        Insights
      </li>
    </ul>}
    <ul className={showIcons ? 'menu-list' : 'menu-list-top'} >
      <li onClick={() => handleNavigation('projects')}>
        {showIcons && <Icon name='list 2x' />}
        Projects
      </li>
      <li onClick={() => handleNavigation('signals')}>
        {showIcons && <Icon name='th 2x' />}
        Signals
      </li>
      <li onClick={() => handleNavigation('roadmap')}>
        {showIcons && <Icon name='map 2x' />}
        Roadmap
      </li>
    </ul>
  </Fragment>
)

export default AppMenu
