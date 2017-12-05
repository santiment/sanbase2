import React from 'react'
import {
  compose,
  pure
} from 'recompose'
import { connect } from 'react-redux'
import { NavLink as Link } from 'react-router-dom'
import logo from './assets/logo_sanbase.png'

export const SideMenu = ({
  user,
  loading,
  logout
}) => (
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

    <br />

    {user.username
      ? <div className='user-auth-control'>
        You are logged in!
        <br />
        <button
          onClick={logout}>
          Log out
        </button>
      </div>
      : <div className='user-auth-control'>
        <Link to={'/login'}>
          Log in
        </Link>
      </div>
      }
  </div>
)

const mapStateToProps = state => {
  return {
    user: state.user.data,
    loading: state.user.isLoading
  }
}

const mapDispatchToProps = dispatch => {
  return {
    logout: () => {
      dispatch({
        type: 'SUCCESS_LOGOUT'
      })
    }
  }
}

const enhance = compose(
  connect(
    mapStateToProps,
    mapDispatchToProps
  ),
  pure
)

export default enhance(SideMenu)
