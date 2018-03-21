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
        ERC20 Projects
      </li>
      <li onClick={() => handleNavigation('currencies')}>
        {showIcons && <Icon name='list 2x' />}
        Currencies
      </li>
    </ul>
  </Fragment>
)

export default AppMenu
