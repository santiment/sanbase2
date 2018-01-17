import React from 'react'
import { Icon } from 'react-fa'
import './AppMenuTop.css'

const AppMenuTop = ({handleNavigation}) => (
  <ul className='menu-list'>
    <li
      onClick={() => handleNavigation('projects')}>
      Projects
    </li>
    <li
      onClick={() => handleNavigation('signals')}>
      Signals
    </li>
    <li
      onClick={() => handleNavigation('roadmap')}>
      Roadmap
    </li>
  </ul>
)

export default AppMenuTop
