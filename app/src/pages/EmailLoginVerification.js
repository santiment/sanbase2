import React from 'react'
import { connect } from 'react-redux'
import {
  compose,
  lifecycle
} from 'recompose'
import * as qs from 'query-string'
import { Link } from 'react-router-dom'
import * as actions from './../actions/types'

export const EmailLoginVerification = ({
  isSuccess,
  isError
}) => {
  if (isError) {
    return (
      <div style={{margin: '1em'}}>
        <h2>You do not have access.</h2>
        <p>Try again later. Maybe, your mail link is old.</p>
        <Link to='/login'>Login</Link>
      </div>
    )
  }
  if (isSuccess) {
    return (
      <div style={{margin: '1em'}}>
        <h2>Email address confirmed</h2>
      </div>
    )
  }
  return (
    <div style={{margin: '1em'}}>
      <h2>Verification...</h2>
    </div>
  )
}

const mapStateToProps = ({rootUi}) => {
  return {
    isError: rootUi.loginError,
    isSuccess: rootUi.loginSuccess
  }
}

const mapDispatchToProps = dispatch => {
  return {
    emailLogin: payload => {
      dispatch({
        type: actions.USER_EMAIL_LOGIN,
        payload
      })
    }
  }
}

const enhance = compose(
  connect(
    mapStateToProps,
    mapDispatchToProps
  ),
  lifecycle({
    componentDidMount () {
      const payload = qs.parse(this.props.location.search)
      this.props.emailLogin(payload)
    }
  })
)

export default enhance(EmailLoginVerification)
