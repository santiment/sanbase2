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
      <div>
        <h2>You do not have access.</h2>
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
    authWithEmail: (qsData, props) => {
      props.verify(qsData)
        .then(({data}) => {
          const { token, user } = data.emailLoginVerify
          GoogleAnalytics.event({
            category: 'User',
            action: 'Success login with email'
          })
          savePrevAuthProvider('email')
          dispatch({
            type: 'SUCCESS_LOGIN',
            token,
            user,
            consent: user.consent_id
          })
          props.changeVerificationStatus('verified')

          if (user.consent_id) {
            window.location.replace(`/consent?consent=${user.consent_id}&token=${token}`)
          } else {
            props.history.push('/')
          }
        })
        .catch(error => {
          GoogleAnalytics.event({
            category: 'User',
            action: 'Failed login with email'
          })
          dispatch({
            type: 'FAILED_LOGIN',
            errorMessage: error
          })
          props.changeVerificationStatus('failed')
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
