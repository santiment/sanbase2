import React from 'react'
import { withRouter } from 'react-router-dom'
import { connect } from 'react-redux'
import { Icon } from 'react-fa'
import {
  withState,
  compose
} from 'recompose'
import 'font-awesome/css/font-awesome.css'
import './MobileMenu.css'
import logo from '../assets/logo_sanbase.png'
import AuthControl from './AuthControl'
import AppMenu from './AppMenu'

const appMenuCls = isMenuOpened => {
  const defaultCls = 'app-menu mobile-app-menu'
  return isMenuOpened
    ? `${defaultCls} overlay`
    : defaultCls
}

const MobileMenu = ({
  toggleMenu,
  isMenuOpened,
  history,
  loading,
  user,
  logout
}) => (
  <div className={appMenuCls(isMenuOpened)}>
    <div className='app-bar'>
      <div
        onClick={() => history.push('/')}
        className='brand'>
        <img
          src={logo}
          width='115'
          height='22'
          alt='SANbase' />
      </div>
      <Icon
        onClick={() => toggleMenu(opened => !opened)}
        name='bars' />
    </div>
    {isMenuOpened &&
      <div className='overlay-content'>
        <AppMenu
          handleNavigation={nextRoute => {
            toggleMenu(opened => !opened)
            history.push(`/${nextRoute}`)
          }} />
        <AuthControl
          login={() => {
            toggleMenu(opened => !opened)
            history.push('/login')
          }}
          isDesktop={false}
          user={user}
          logout={() => {
            logout()
          }} />
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
  withState('isMenuOpened', 'toggleMenu', false)
)

export default enhance(MobileMenu)
