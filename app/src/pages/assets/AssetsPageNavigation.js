import React from 'react'
import { NavLink as Link } from 'react-router-dom'
import WatchlistsPopup from './../../components/WatchlistPopup/WatchlistsPopup'
import './AssetsPageNavigation.css'

const MyListBtn = (
  <div className='projects-navigation-list__page-link'>Watchlists</div>
)

const AssetsPageNavigation = ({ isLoggedIn = false, location: { search } }) => {
  return (
    <div className='projects-navigation'>
      <div className='projects-navigation-list'>
        <Link
          activeClassName='projects-navigation-list__page-link--active'
          className='projects-navigation-list__page-link'
          to={{ pathname: '/assets/all', search }}
        >
          All Assets
        </Link>
        <Link
          activeClassName='projects-navigation-list__page-link--active'
          className='projects-navigation-list__page-link'
          to={{ pathname: '/assets/erc20', search }}
        >
          ERC20 Assets
        </Link>
        <Link
          activeClassName='projects-navigation-list__page-link--active'
          className='projects-navigation-list__page-link'
          to={{ pathname: '/assets/currencies', search }}
        >
          Currencies
        </Link>
        <Link
          activeClassName='projects-navigation-list__page-link--active'
          className='projects-navigation-list__page-link'
          to={'/ethereum-spent'}
        >
          ETH Spent
        </Link>
        <WatchlistsPopup
          isNavigation
          isLoggedIn={isLoggedIn}
          trigger={MyListBtn}
          searchParams={search}
        />
      </div>
    </div>
  )
}

export default AssetsPageNavigation
