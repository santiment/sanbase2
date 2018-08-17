import React, { Fragment } from 'react'
import { Link } from 'react-router-dom'
import { compose } from 'recompose'
import { connect } from 'react-redux'
import 'font-awesome/css/font-awesome.css'
import logo from '../assets/logo_sanbase.png'
import HeaderDropdownMenu from './HeaderDropdownMenu.js'
import Search from './Search/SearchContainer'
import * as actions from './../actions/types'
import AnalysisDropdownMenu from './AnalysisDropdownMenu'
import SmoothDD from './SmoothDropdown/SmoothDD'
import SmoothDDItem from './SmoothDropdown/SmoothDDItem'
import './AppMenu.css'
import './TopMenu.css'

export const TopMenu = ({ isLoggedin, logout, location, projects = [] }) => (
  <div className='app-menu'>
    <div className='container'>
      <div className='left'>
        <Link to={'/'} className='brand'>
          <img src={logo} width='115' height='22' alt='SANbase' />
        </Link>
        <Search />
      </div>
      <div className='right'>
        <SmoothDD id='nav-dropdown'>
          <ul className='menu-list-top'>
            <Link className='app-menu__page-link' to={'/projects'}>
              Assets
            </Link>
            <AnalysisDropdownMenu />
          </ul>
          <HeaderDropdownMenu isLoggedin={isLoggedin} logout={logout} />
          <SmoothDDItem
            id='testing'
            trigger={<p>testing 123. it's first drop</p>}
          >
            testing popup
          </SmoothDDItem>
        </SmoothDD>
      </div>
    </div>
  </div>
)

const mapStateToProps = ({ user = {} }) => {
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

const enhance = compose(connect(mapStateToProps, mapDispatchToProps))

export default enhance(TopMenu)
