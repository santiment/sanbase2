import React from 'react'
import {
  Route,
  NavLink as Link,
  Switch
} from 'react-router-dom'
import './App.css'
import Login from './Login'
import Cashflow from './Cashflow'
import logo from './assets/logo_sanbase.png'
import withSizes from 'react-sizes'

export const SideMenu = () => (
  <div className='side-menu'>
    <div className='brand'>
      <img
        src={logo}
        width='115'
        height='22'
        alt='SANbase' />
    </div>
    <i
      className='fa fa-bars fa-2x toggle-btn'
      data-toggle='collapse'
      data-target='#menu-content' />
    <div className='menu-list'>
      <ul id='menu-content' className='menu-content collapse out'>
        <li>
          Dashboard (tbd)
        </li>
        <li data-toggle='collapse' data-target='#products'>
          Data-feeds
        </li>
        <ul className='sub-menu' id='products'>
          <li>Overview (tbd)</li>
          <li>
            <Link
              activeClassName='selected'
              to='/cashflow'>
              Cash Flow
            </Link>
          </li>
        </ul>
        <li>
          Signals
        </li>
        <li>
          Roadmap
        </li>
      </ul>
    </div>
  </div>
)

export const App = ({isDesktop}) => (
  <div className='App'>
    {isDesktop && <SideMenu />}
    <Switch>
      <Route exact path='/cashflow' component={Cashflow} />
      <Route path={'/login'} component={Login} />
      <Route exact path={'/'} component={Cashflow} />
    </Switch>
  </div>
)

const mapSizesToProps = ({ width }) => ({
  isDesktop: width > 620
})

export default withSizes(mapSizesToProps)(App)
