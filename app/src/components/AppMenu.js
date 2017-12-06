import React from 'react'
import { Icon } from 'react-fa'
import './AppMenu.css'

const AppMenu = ({handleNavigation}) => (
  <ul className='menu-list'>
    <li>
      <Icon
        className='toggle-btn'
        name='home 2x' />
      Dashboard (tbd)
    </li>
    <li>
      <Icon
        name='list 2x' />
      Data-feeds
    </li>
    <ul className='sub-menu'>
      <li>
        <Icon
          name='circle' />
        Overview (tbd)
      </li>
      <li
        onClick={() => handleNavigation('cashflow')}>
        <Icon
          name='circle' />
        Cashflow
      </li>
    </ul>
    <li
      onClick={() => handleNavigation('signals')}>
      <Icon
        name='th 2x' />
      Signals
    </li>
    <li
      onClick={() => handleNavigation('roadmap')}>
      <Icon
        name='comment-o 2x' />
      Roadmap
    </li>
  </ul>
)

export default AppMenu
