import React from 'react'
import { NavLink as Link } from 'react-router-dom'
import AssetsListPopup from './../../components/AssetsListPopup/AssetsListPopup'
import './AssetsPageNavigation.css'

const MyListBtn = (
  <div className='projects-navigation-list__page-link'>Watchlists</div>
)

const AssetsPageNavigation = ({ isLoggedIn = false }) => {
  return (
    <div className='projects-navigation'>
      <div className='projects-navigation-list'>
        <Link
          activeClassName='projects-navigation-list__page-link--active'
          className='projects-navigation-list__page-link'
          to={'/assets/erc20'}
        >
          ERC20 Projects
        </Link>
        <Link
          activeClassName='projects-navigation-list__page-link--active'
          className='projects-navigation-list__page-link'
          to={'/assets/currencies'}
        >
          Currencies
        </Link>
        {isLoggedIn && (
          <Link
            activeClassName='projects-navigation-list__page-link--active'
            className='projects-navigation-list__page-link'
            to={'/favorites'}
          >
            Favorites
          </Link>
        )}
        {isLoggedIn && (
          <AssetsListPopup
            isNavigation
            isLoggedIn={isLoggedIn}
            trigger={MyListBtn}
          />
        )}
        <Link
          activeClassName='projects-navigation-list__page-link--active'
          className='projects-navigation-list__page-link'
          to={'/projects/ethereum'}
        >
          More data about Ethereum
        </Link>
      </div>
    </div>
  )
}

export default AssetsPageNavigation
