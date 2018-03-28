import React from 'react'
import { Popup, Button, Icon } from 'semantic-ui-react'
import './AppMenu.css'

const AppMenu = ({handleNavigation, showIcons = false, showInsights = false}) => (
  <ul className={showIcons ? 'menu-list' : 'menu-list-top'} >
    <li onClick={() => handleNavigation('projects')}>
      {showIcons && <Icon name='list 2x' />}
      Projects
    </li>
    <li
      onClick={() => handleNavigation('signals')}>
      <Icon name='th 2x' />
      Signals
    </li>
    <li onClick={() => handleNavigation('roadmap')}>
      {showIcons && <Icon name='map 2x' />}
      Roadmap
    </li>
  </ul>
)

export default AppMenu
