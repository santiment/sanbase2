import React from 'react'
import { connect } from 'react-redux'
import {
  compose,
  withState,
  lifecycle
} from 'recompose'
import * as qs from 'query-string'
import { graphql } from 'react-apollo'
import gql from 'graphql-tag'

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
      <div>
        <h2>Verification...</h2>
      </div>
    )
  }
  if (verificationStatus === 'failed') {
    return (
      <div>
        <h2>You don't have access.</h2>
      </div>
    )
  }
  return (
    <div>
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
          dispatch({
            type: 'SUCCESS_LOGIN',
            token,
            user
          })
          props.changeVerificationStatus('verified')
          props.history.push('/')
        })
        .catch(error => {
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
  graphql(emailLoginVerifyGQL, {
    name: 'emailLoginVerify',
    props: ({ emailLoginVerify }) => ({
      verify: ({token, email}) => emailLoginVerify({ variables: { token, email } })
    }),
    options: { fetchPolicy: 'network-only' }
  }),
  lifecycle({
    componentDidMount () {
      const qsData = qs.parse(this.props.location.search)
      this.props.authWithEmail(qsData, this.props)
    }
  })
)

export default enhance(EmailLoginVerification)
