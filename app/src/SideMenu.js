import React from 'react'
import {
  withRouter,
  NavLink as Link
} from 'react-router-dom'
import {
  compose,
  pure
} from 'recompose'
import {
  Button
} from 'semantic-ui-react'
import { connect } from 'react-redux'
import { Icon } from 'react-fa'
import 'font-awesome/css/font-awesome.css'
import logo from './assets/logo_sanbase.png'
import './SideMenu.css'

export const SideMenu = ({
  user,
  loading,
  logout,
  history
}) => (
  <div className='side-menu'>
    <div className='brand'>
      <img
        src={logo}
        width='115'
        height='22'
        alt='SANbase' />
    </div>
    <div className='menu-list'>
      <ul id='menu-content' className='menu-content collapse out'>
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
        <ul className='sub-menu' id='products'>
          <li>
            <Icon
              name='circle' />
            Overview (tbd)
          </li>
          <li
            onClick={() => history.push('/cashflow')}>
            <Icon
              name='circle' />
            <Link
              activeClassName='selected'
              to='/cashflow'>
              Cash Flow
            </Link>
          </li>
        </ul>
        <li
          onClick={() => history.push('/signals')}>
          <Icon
            name='th 2x' />
          Signals
        </li>
        <li
          onClick={() => history.push('/roadmap')}>
          <Icon
            name='comment-o 2x' />
          <Link
            activeClassName='selected'
            to='/roadmap'>
            Roadmap
          </Link>
        </li>
      </ul>
    </div>
    {user.username
      ? <div className='user-auth-control'>
        You are logged in!
        <br />
        <a href='#' onClick={logout}>
          Log out
        </a>
      </div>
      : <div className='user-auth-control'>
        <Button
          basic
          color='green'
          onClick={() => history.push('/login')}>
          Log in
        </Button>
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
  withRouter,
  pure
)

export default enhance(SideMenu)
