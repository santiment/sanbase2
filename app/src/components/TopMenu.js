import React from 'react'
import { withRouter } from 'react-router-dom'
import {
  compose,
  pure
} from 'recompose'
import { connect } from 'react-redux'
import 'font-awesome/css/font-awesome.css'
import logo from '../assets/logo_sanbase.png'
import AppMenuTop from './AppMenuTop'
import AuthControl from './AuthControl'
import Search from './Search'
import './TopMenu.css'

export const TopMenu = ({
  user,
  loading,
  logout,
  history,
  projects
 }) => (
  <div className='top-menu'>
    <div className='left'>
      <div
        onClick={() => history.push('/')}
        className='brand'>
        <img
          src={logo}
          width='115'
          height='22'
          alt='SANbase' />
      </div>
      <Search
        onSelectProject={ticker => history.push(`/projects/${ticker.toLowerCase()}`)}
        projects={projects} />
    </div>
    <div className='right'>
      <AppMenuTop
        handleNavigation={nextRoute => {
          history.push(`/${nextRoute}`)
        }} />
      <AuthControl
        login={() => history.push('/login')}
        user={user}
        logout={logout} />
    </div>
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

export default enhance(TopMenu)
