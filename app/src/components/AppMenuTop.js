import React from 'react'
import './AppMenuTop.css'

const AppMenuTop = ({handleNavigation}) => (
  <ul className='menu-list-top'>
    <li
      onClick={() => handleNavigation('projects')}>
      Projects
    </li>
    <li onClick={() => handleNavigation('events')}>
      Insights
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
