import React from 'react'
import { Icon } from 'react-fa'
import './AppMenu.css'

const AppMenu = ({handleNavigation}) => (
  <ul className='menu-list'>
    <li
      onClick={() => handleNavigation('projects')}>
      <Icon name='list 2x' />
      Projects
    </li>
    <li
      onClick={() => handleNavigation('events')}>
      <Icon
        name='map 2x' />
      Events
    </li>
    <li
      onClick={() => handleNavigation('signals')}>
      <Icon name='th 2x' />
      Signals
    </li>
    <li
      onClick={() => handleNavigation('roadmap')}>
      <Icon
        name='map 2x' />
      Roadmap
    </li>
  </ul>
)

export default AppMenu
