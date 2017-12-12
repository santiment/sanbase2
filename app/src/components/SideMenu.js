import React from 'react'
import { withRouter } from 'react-router-dom'
import {
  compose,
  pure
} from 'recompose'
import { connect } from 'react-redux'
import 'font-awesome/css/font-awesome.css'
import logo from '../assets/logo_sanbase.png'
import AppMenu from './AppMenu'
import AuthControl from './AuthControl'
import './SideMenu.css'

export const SideMenu = ({
  user,
  loading,
  logout,
  history
}) => (
  <div className='side-menu'>
    <div
      onClick={() => history.push('/')}
      className='brand'>
      <img
        src={logo}
        width='115'
        height='22'
        alt='SANbase' />
    </div>
    <AppMenu
      handleNavigation={nextRoute => {
        history.push(`/${nextRoute}`)
      }} />
    <AuthControl
      login={() => history.push('/login')}
      user={user}
      logout={logout} />
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
