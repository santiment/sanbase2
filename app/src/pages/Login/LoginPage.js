import React from 'react'
import * as qs from 'query-string'
import { connect } from 'react-redux'
import { Redirect } from 'react-router-dom'
import Panel from './../../components/Panel'
import Login from './Login'
import './Login.css'

export const LoginPage = ({
  user,
  isDesktop,
  location
}) => {
  if (location) {
    const qsData = qs.parse(location.search)
    if (qsData && qsData.redirect_to && user.token) {
      return <Redirect to={qsData.redirect_to} />
    }
  }
  if (user.data.hasOwnProperty('username') || user.token) {
    return <Redirect to='/' />
  }
  return (
    <div className='page login wrapper'>
      <Panel className='login-inner'>
        <Login isDesktop={isDesktop} />
      </Panel>
    </div>
  )
}

const mapStateToProps = state => {
  return {
    user: state.user
  }
}

export default connect(mapStateToProps)(LoginPage)
