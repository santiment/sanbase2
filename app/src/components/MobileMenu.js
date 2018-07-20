import React from 'react'
import { withRouter, NavLink as Link } from 'react-router-dom'
import cx from 'classnames'
import { connect } from 'react-redux'
import { Icon } from 'react-fa'
import { Button } from 'semantic-ui-react'
import { compose, withStateHandlers } from 'recompose'
import 'font-awesome/css/font-awesome.css'
import './MobileMenu.css'
import logo from '../assets/logo_sanbase.png'
import * as actions from './../actions/types'

const MobileMenu = ({
  isOpened = false,
  toggleMenu,
  history,
  isLogined,
  logout
}) => (
  <div
    className={cx({
      'mobile-app-menu': true,
      overlay: isOpened
    })}
  >
    <div className='app-bar'>
      <div onClick={() => history.push('/')} className='brand'>
        <img src={logo} width='115' height='22' alt='SANbase' />
      </div>
      <Icon
        className={isOpened ? 'close-btn--rotation' : ''}
        onClick={toggleMenu}
        name={isOpened ? 'close' : 'bars'}
      />
    </div>
    {isOpened && (
      <div className='overlay-content'>
        <div className='navigation-list'>
          <Link onClick={toggleMenu} to={'/signals'}>
            Signals
          </Link>
          <Link onClick={toggleMenu} to={'/roadmap'}>
            Roadmap
          </Link>
          <Link onClick={toggleMenu} to={'/projects'}>
            ERC20 Projects
          </Link>
          <Link onClick={toggleMenu} to={'/currencies'}>
            Currencies
          </Link>
        </div>
        {isLogined ? (
          <Button
            color='orange'
            onClick={() => {
              toggleMenu()
              logout()
            }}
          >
            Logout
          </Button>
        ) : (
          <Button
            color='green'
            onClick={() => {
              toggleMenu()
              history.push('/login')
            }}
          >
            Login
          </Button>
        )}
      </div>
    )}
  </div>
)

const mapStateToProps = ({ user = {} }) => {
  return {
    isLogined: !!user.token
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
  withRouter,
  connect(mapStateToProps, mapDispatchToProps),
  withStateHandlers(
    { isOpened: false },
    {
      toggleMenu: ({ isOpened }) => () => ({ isOpened: !isOpened })
    }
  )
)

export default enhance(MobileMenu)
