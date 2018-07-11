import React from 'react'
import { Link } from 'react-router-dom'
import { compose } from 'recompose'
import { connect } from 'react-redux'
import 'font-awesome/css/font-awesome.css'
import logo from '../assets/logo_sanbase.png'
import HeaderDropdownMenu from './HeaderDropdownMenu.js'
import Search from './SearchContainer'
import * as actions from './../actions/types'
import './AppMenu.css'
import './TopMenu.css'

export const TopMenu = ({
 isLoggedin,
 logout,
 location,
 projects = []
}) => (
  <div className='app-menu'>
    <div className='container'>
      <div className='left'>
        <Link to={'/'} className='brand'>
          <img
            src={logo}
            width='115'
            height='22'
            alt='SANbase' />
        </Link>
        <Search />
      </div>
      <div className='right'>
        <ul className='menu-list-top' >
          <Link
            className='app-menu__page-link'
            to={'/projects'}>
            Markets
          </Link>
          <Link
            className='app-menu__page-link'
            to={'/signals'}>
            Signals
          </Link>
        </ul>
        <HeaderDropdownMenu
          isLoggedin={isLoggedin}
          logout={logout} />
      </div>
    </div>
  </div>
)

const mapStateToProps = ({user = {}}) => {
  return {
    isLoggedin: !!user.token
  }
}

const mapDispatchToProps = dispatch => {
  return {
    logout: () => {
      dispatch({
        type: actions.USER_LOGOUT_SUCCESS
      })
    }
  }
}

const enhance = compose(
  connect(
    mapStateToProps,
    mapDispatchToProps
  )
)

export default enhance(TopMenu)
