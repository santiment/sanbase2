import React from 'react'
import { NavLink as Link } from 'react-router-dom'
import SmoothDropdownItem from './../../components/SmoothDropdown/SmoothDropdownItem'
import SmoothDropdown from './../../components/SmoothDropdown/SmoothDropdown'
import WatchlistsPopup from './../../components/WatchlistPopup/WatchlistsPopup'

import './AssetsPageNavigation.css'

const MyListBtn = (
  <div className='projects-navigation-list__page-link'>Watchlists</div>
)

const EthereumBtn = (
  <div className='projects-navigation-list__page-link'>Ethereum</div>
)

const CategoriesBtn = (
  <div className='projects-navigation-list__page-link'>Categories</div>
)

const AssetsPageNavigation = ({ isLoggedIn = false, location: { search } }) => (
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
        to={{ pathname: '/assets/currencies', search }}
      >
        Currencies
      </Link>
      <SmoothDropdown>
        <SmoothDropdownItem
          className='assets-navigation-popup'
          trigger={EthereumBtn}
        >
          <Link
            activeClassName='assets-navigation-list__dropdown-link--active'
            className='assets-navigation-list__dropdown-link'
            to={'/assets/erc20'}
          >
            ERC20 Assets
          </Link>
          <Link
            activeClassName='projects-navigation-list__dropdown-link--active'
            className='assets-navigation-list__dropdown-link'
            to={'/ethereum-spent'}
          >
            ETH Spent
          </Link>
        </SmoothDropdownItem>
        <SmoothDropdownItem
          className='assets-navigation-popup'
          trigger={CategoriesBtn}
        >
          <Link
            activeClassName='assets-navigation-list__dropdown-link--active'
            className='assets-navigation-list__dropdown-link'
            to={'/assets/list?name=stablecoins@86#shared'}
          >
            Stablecoins
          </Link>
          <Link
            activeClassName='projects-navigation-list__dropdown-link--active'
            className='assets-navigation-list__dropdown-link'
            to={'/assets/list?name=usa@138#shared'}
          >
            USD based assets
          </Link>
          <Link
            activeClassName='projects-navigation-list__dropdown-link--active'
            className='assets-navigation-list__dropdown-link'
            to={'/assets/list?name=dex@127#shared'}
          >
            Decentralized Exchanges Tokens (DEXs)
          </Link>
        </SmoothDropdownItem>
        <SmoothDropdownItem trigger={MyListBtn}>
          <WatchlistsPopup
            isNavigation
            searchParams={search}
            isLoggedIn={isLoggedIn}
          />
        </SmoothDropdownItem>
      </SmoothDropdown>
    </div>
  </div>
)

export default AssetsPageNavigation
