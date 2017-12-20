import React from 'react'
import { connect } from 'react-redux'
import { Redirect } from 'react-router-dom'
import {
  compose,
  pure
} from 'recompose'
import {
  Form,
  Input,
  Message,
  Divider,
  Button
} from 'semantic-ui-react'
import { graphql, withApollo } from 'react-apollo'
import gql from 'graphql-tag'
import copy from 'copy-to-clipboard'
import Balance from './../components/Balance'
import './Account.css'

let emailInputRef

const requestChangeEmailGQL = gql`
  mutation changeEmail($email: String!) {
    changeEmail(
      email: $email) {
        email
      }
}`

const handleEmailInputRef = (c) => {
  emailInputRef = c
}

export const Account = ({
  user,
  loading,
  logout,
  changeEmailReq,
  requestChangeEmail
}) => {
  if (user && !user.username) {
    return (
      <Redirect to={{
        pathname: '/'
      }} />
    )
  }
  return (
    <div className='page account'>
      <div className='page-head'>
        <h1>Account settings</h1>
      </div>
      <div className='panel'>
        <Form loading={loading}>
          <Form.Field>
            <label>Email</label>
            <Input
              placeholder={user.email || ''}
              ref={handleEmailInputRef}
              action={{
                color: 'teal',
                labelPosition: 'right',
                icon: 'save',
                content: 'Save',
                onClick: () => requestChangeEmail(emailInputRef.inputRef.value, changeEmailReq)
              }}
            />
            {!user.email &&
              <Message
                warning
                visible
                header='Email is not added yet!'
                list={[
                  'For access your dashboard from mobile device, you should add email address.'
                ]}
              />}
          </Form.Field>
          <Form.Field>
            <label>Username ( Eth Public Key )</label>
            <Input
              input={{readOnly: true}}
              action={{
                color: 'teal',
                labelPosition: 'right',
                icon: 'copy',
                content: 'Copy',
                onClick: () => copy(user.username)
              }}
              defaultValue={user.username}
            />
          </Form.Field>
          <h3>Wallets</h3>
          <Divider />
          <Balance user={user} />
          <h3>Sessions</h3>
          <Divider />
          <p>Your current session</p>
          <Button
            basic
            color='red'
            onClick={logout}
          >Log out</Button>
        </Form>
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
    },
    requestChangeEmail: (newEmail, changeEmailReq) => {
      changeEmailReq({variables: { newEmail }})
      .then(({ data }) => {
        dispatch({
          type: 'CHANGE_EMAIL_USER',
          email: data.changeEmail.email
        })
      })
      .catch((error) => {
        console.error(error)
      })
    }
  }
}

const enhance = compose(
  connect(
    mapStateToProps,
    mapDispatchToProps
  ),
  withApollo,
  graphql(requestChangeEmailGQL, {
    name: 'changeEmailReq',
    options: { fetchPolicy: 'network-only' }
  }),
  pure
)

export default enhance(Account)
