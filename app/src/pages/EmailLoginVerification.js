import React from 'react'
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
        id
        email
        username
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
      <h2>Email address confirmed!</h2>
    </div>
  )
}

const enhance = compose(
  withState('verificationStatus', 'changeVerificationStatus', 'pending'),
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
      this.props.verify(qsData)
        .then(data => {
          const { token, user } = data.emailLoginVerify
          console.log(token, user)
          this.props.changeVerificationStatus('verified')
        })
        .catch(error => {
          if (/\bLogin failed/.test(error)) {
            this.props.changeVerificationStatus('failed')
          } else {
            throw new Error(error)
          }
        })
    }
  })
)

export default enhance(EmailLoginVerification)
