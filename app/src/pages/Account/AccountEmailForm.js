import React from 'react'
import { Form as ReactForm } from 'react-form'
import Raven from 'raven-js'
import { EmailField } from '../../pages/Login/EmailLogin'
import { FadeIn } from 'animate-components'
import { Button } from 'semantic-ui-react'
import { graphql } from 'react-apollo'
import { changeEmailGQL } from './accountGQL'

const AccountEmailForm = ({ user, changeEmailQuery, changeEmail, isEmailPending, setFormStatus, errorValidator, successValidator }) => {
  return (
    <ReactForm
      validateError={errorValidator}
      validateSuccess={successValidator}
      onSubmitFailure={(error, ...rest) => {
        setFormStatus('ERROR', true)
        setFormStatus('SUCCESS', false)
        Raven.captureException(`User try to change email: ${error} ${rest}`)
      }}
      onSubmit={(values, _, formApi) => {
        if (!values.email) return // To fix react-form bug, that leads to empty graphql query

        setFormStatus('PENDING', true)
        setFormStatus('SUCCESS', false)
        changeEmailQuery({ variables: { ...values } })
          .then(() => {
            setFormStatus('PENDING', false)
            setFormStatus('ERROR', false)
            setFormStatus('SUCCESS', true)
            changeEmail(values.email)
            formApi.resetAll()
          })
          .catch(error => {
            setFormStatus('PENDING', false)
            setFormStatus('ERROR', true)
            Raven.captureException(`User try to change email: ${error}`)
          })
      }}
    >
      {formApi => (
        <form
          className='account-settings-email'
          onSubmit={formApi.submitForm}
          autoComplete='off'
        >
          <EmailField
            autoFocus={false}
            disabled={isEmailPending}
            placeholder={user.email || undefined}
            className='account-settings-email__input'
            formApi={formApi}
          />

          {formApi.getSuccess().email &&
            <FadeIn
              className='account-settings-email__button-container'
              duration='0.7s'
              timingFunction='ease-in'
              as='div'
            >
              <Button
                disabled={!formApi.getSuccess().email || isEmailPending}
                positive={!!formApi.getSuccess().email}
                type='submit'
              >
                {isEmailPending ? 'Waiting...' : 'Submit'}
              </Button>
            </FadeIn>}
        </form>
      )}
    </ReactForm>
  )
}

export default graphql(changeEmailGQL, { name: 'changeEmailQuery' })(AccountEmailForm)
