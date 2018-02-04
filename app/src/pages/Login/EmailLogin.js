import React, { Fragment } from 'react'
import Raven from 'raven-js'
import {
  Button,
  Message
} from 'semantic-ui-react'
import {
  compose,
  withState
} from 'recompose'
import { graphql } from 'react-apollo'
import gql from 'graphql-tag'
import { Form } from 'react-form'
import ReactFormInput from '../../components/react-form-semantic-ui-react/ReactFormInput'
import './EmailLogin.css'
const validate = require('validate.js')

const validateFields = (email, username) => {
  var constraints = {
    email: {
      email: true
    },
    username: {
      length: {minimum: 3}
    }
  }
  return validate({email, username}, constraints)
}

const errorValidator = ({email, username}) => {
  const validation = validateFields(email, username)
  return {
    email: validation && validation.email,
    username: validation && validation.username
  }
}

const successValidator = ({email, username}) => {
  const validation = validateFields(email, username)
  return {
    email: typeof validation === 'undefined' || !validation.email,
    username: typeof validation === 'undefined' || !validation.username
  }
}

const isErrorEmail = formApi => (
  !!formApi.getValue().email &&
    formApi.getTouched().email &&
    !!formApi.getError().email
)

const isErrorUsername = formApi => (
  !!formApi.getValue().username &&
    formApi.getTouched().username &&
    !!formApi.getError().username
)

const EmailField = ({formApi}) => (
  <Fragment>
    <label>Email</label>
    <ReactFormInput
      fluid
      autoFocus
      initvalue=''
      type='email'
      field='email'
      error={isErrorEmail(formApi)}
      className='email-input'
      placeholder='you@domain.com' />
    {isErrorEmail(formApi) &&
      <Message negative>
        {formApi.getError().email}
      </Message>}
  </Fragment>
)

const UsernameField = ({formApi}) => {
  return (
    <Fragment>
      <label>Username</label>
      <ReactFormInput
        fluid
        type='text'
        field='username'
        error={isErrorUsername(formApi)}
        className='username-input'
        placeholder='Your name' />
      {isErrorUsername(formApi) &&
        <Message negative>
          {formApi.getError().username}
        </Message>}
    </Fragment>
  )
}

const EmailLogin = ({
  emailLogin,
  isPending = false,
  isError = false,
  isSuccess = false,
  onPending,
  onError,
  onSuccess
}) => {
  if (isSuccess) {
    return (
      <div>
        <p>We sent an email to you. Please login in to email provider and click the confirm link.</p>
        <p>Waiting for your confirmation...</p>
      </div>
    )
  }
  if (isError) {
    return (
      <div>
        <p>Something going wrong on our server.</p>
        <p>Please try again.</p>
      </div>
    )
  }
  return (
    <div>
      <p>To sign up or log in, fill in your email address below:</p>
      <Form
        validateError={errorValidator}
        validateSuccess={successValidator}
        onSubmit={values => {
          onPending(true)
          emailLogin({variables: {...values}})
            .then(data => {
              onPending(false)
              onSuccess(true)
            })
            .catch(error => {
              onPending(false)
              onError(true)
              Raven.captureException(error)
            })
        }}>
        {formApi => (
          <form
            className='email-login-form'
            onSubmit={formApi.submitForm}
            autoComplete='off'>
            <EmailField formApi={formApi} />
            {formApi.successes.email &&
              <UsernameField formApi={formApi} />}
            <div className='email-form-control'>
              <Button
                disabled={
                  !formApi.getSuccess().email ||
                  !formApi.getSuccess().username ||
                  isPending
                }
                positive={!!formApi.getSuccess().email && !!formApi.getSuccess().username}
                type='submit'>
                {isPending ? 'Waiting...' : 'Continue'}
              </Button>
            </div>
          </form>
        )}
      </Form>
    </div>
  )
}

const emailLoginGQL = gql`
  mutation emailLogin($email: String!, $username: String!) {
    emailLogin(email: $email, username: $username) {
      success
    }
  }
`

export default compose(
  withState('isPending', 'onPending', false),
  withState('isError', 'onError', false),
  withState('isSuccess', 'onSuccess', false),
  graphql(emailLoginGQL, {
    name: 'emailLogin',
    options: { fetchPolicy: 'network-only' }
  })
)(EmailLogin)
