import React from 'react'
import { Link } from 'react-router-dom'
import { connect } from 'react-redux'
import 'font-awesome/css/font-awesome.css'
import { Label } from 'semantic-ui-react'
import logo from '../assets/logo_sanbase.png'
import HeaderDropdownMenu from './HeaderDropdownMenu.js'
import Search from './Search/SearchContainer'
import * as actions from './../actions/types'
import AnalysisDropdownMenu from './AnalysisDropdownMenu'
import SmoothDropdown from './SmoothDropdown/SmoothDropdown'
import { checkIsLoggedIn } from './../pages/UserSelectors'
import './AppMenu.css'
import './TopMenu.css'

export const TopMenu = ({ isLoggedin, logout }) => (
  <div className='app-menu'>
    <div className='container'>
      <div className='left'>
        <Link to='/' className='brand'>
          <img src={logo} width='115' height='22' alt='SANbase' />
        </Link>
        <Search />
      </div>
      <SmoothDropdown className='right'>
        <div className='menu-list-top'>
          <Link className='app-menu__page-link' to='/trends'>
            Trends{' '}
            <Label color='green' horizontal>
              new
            </Label>
          </Link>
          <Link className='app-menu__page-link' to='/assets'>
            Assets
          </Link>
          <AnalysisDropdownMenu />
        </div>
        <HeaderDropdownMenu isLoggedin={isLoggedin} logout={logout} />
      </SmoothDropdown>
    </div>
  </div>
)

const mapStateToProps = state => ({ isLoggedin: checkIsLoggedIn(state) })

const mapDispatchToProps = dispatch => {
  return {
    logout: () => {
      dispatch({
        type: actions.USER_LOGOUT_SUCCESS
      })
    }
  }
}

export default connect(mapStateToProps, mapDispatchToProps)(TopMenu)
