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
  let consent = ''
  if (location) {
    const qsData = qs.parse(location.search)
    if (qsData && qsData.redirect_to && user.token) {
      return <Redirect to={qsData.redirect_to} />
    }
    if (qsData && qsData.consent) {
      consent = qsData.consent
    }
  }
  if (user.data.hasOwnProperty('username') || user.token) {
    if (consent) {
      window.location.replace(`/consent?consent=${consent}&token=${user.token}`)
    }
    return <Redirect to='/' />
  }
  return (
    <div className='page login wrapper'>
      <Panel className='login-inner'>
        <Login isDesktop={isDesktop} consent={consent} />
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
