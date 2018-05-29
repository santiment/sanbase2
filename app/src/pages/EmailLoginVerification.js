import React from 'react'
import { connect } from 'react-redux'
import GoogleAnalytics from 'react-ga'
import {
  compose,
  withState,
  lifecycle
} from 'recompose'
import * as qs from 'query-string'
import { graphql, withApollo } from 'react-apollo'
import gql from 'graphql-tag'
import { savePrevAuthProvider } from './../utils/localStorage'

const emailLoginVerifyGQL = gql`
  mutation emailLoginVerify($email: String!, $token: String!) {
    emailLoginVerify(
      email: $email,
      token: $token
    ) {
      token
      user {
        id,
        email,
        username,
        consent_id,
        ethAccounts {
          address,
          sanBalance
        }
      }
    }
  }
`

export const EmailLoginVerification = ({verificationStatus = 'pending'}) => {
  if (verificationStatus === 'pending') {
    return (
      <div style={{margin: '1em'}}>
        <h2>Verification...</h2>
      </div>
    )
  }
  if (verificationStatus === 'failed') {
    return (
      <div style={{margin: '1em'}}>
        <h2>You do not have access.</h2>
      </div>
    )
  }
  return (
    <div style={{margin: '1em'}}>
      <h2>Email address confirmed</h2>
    </div>
  )
}

const mapStateToProps = state => {
  return {
    user: state.user
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
          props.client.resetStore()

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
  withState('verificationStatus', 'changeVerificationStatus', 'pending'),
  connect(
    mapStateToProps,
    mapDispatchToProps
  ),
  withApollo,
  graphql(emailLoginVerifyGQL, {
    name: 'emailLoginVerify',
    props: ({ emailLoginVerify }) => ({
      verify: ({token, email}) => emailLoginVerify({ variables: { token, email } })
    })
  }),
  lifecycle({
    componentDidMount () {
      const qsData = qs.parse(this.props.location.search)
      this.props.authWithEmail(qsData, this.props)
    }
  })
)

export default enhance(EmailLoginVerification)
