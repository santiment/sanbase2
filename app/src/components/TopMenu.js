import React from 'react'
import { withRouter } from 'react-router-dom'
import * as qs from 'query-string'
import { compose } from 'recompose'
import { connect } from 'react-redux'
import 'font-awesome/css/font-awesome.css'
import logo from '../assets/logo_sanbase.png'
import AppMenu from './AppMenu'
import AuthControl from './AuthControl'
import Search from './SearchContainer'
import './TopMenu.css'

export const TopMenu = ({
  user,
  loading,
  logout,
  history,
  location,
  projects = []
 }) => {
  const qsData = qs.parse(location.search)
  return (
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
        <Search />
      </div>
      <div className='right'>
        <AppMenu
          showInsights={qsData && qsData.insights}
          handleNavigation={nextRoute => {
            history.push(`/${nextRoute}`)
          }} />
        <AuthControl
          login={() => history.push('/login')}
          openSettings={() => {
            history.push('/account')
          }}
          user={user}
          logout={logout} />
      </div>
    </div>
  )
}

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
  withRouter
)

export default enhance(TopMenu)
