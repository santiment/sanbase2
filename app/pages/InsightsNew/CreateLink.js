import React from 'react'
import { Button, Message } from 'semantic-ui-react'
import { Form } from 'react-form'
import ReactFormInput from '../../components/react-form-semantic-ui-react/ReactFormInput'

const errorValidator = values => {
  return {
    link:
      !values.link ||
      !values.link.match(
        /(https?:\/\/(?:www\.|(?!www))[a-zA-Z0-9][a-zA-Z0-9-]+[a-zA-Z0-9]\.[^\s]{2,}|www\.[a-zA-Z0-9][a-zA-Z0-9-]+[a-zA-Z0-9]\.[^\s]{2,}|https?:\/\/(?:www\.|(?!www))[a-zA-Z0-9]\.[^\s]{2,}|www\.[a-zA-Z0-9]\.[^\s]{2,})/
      )
        ? 'Input must contain a valid URL. (e.g. https://twitter/insight)'
        : null
  }
}

const successValidator = values => {
  return {
    link:
      values.link &&
      values.link.match(
        /(https?:\/\/(?:www\.|(?!www))[a-zA-Z0-9][a-zA-Z0-9-]+[a-zA-Z0-9]\.[^\s]{2,}|www\.[a-zA-Z0-9][a-zA-Z0-9-]+[a-zA-Z0-9]\.[^\s]{2,}|https?:\/\/(?:www\.|(?!www))[a-zA-Z0-9]\.[^\s]{2,}|www\.[a-zA-Z0-9]\.[^\s]{2,})/
      )
        ? 'Thank you for entering link'
        : null
  }
}

const isError = formApi =>
  !!formApi.getValue().link &&
  formApi.getValue().link.length > 2 &&
  formApi.getTouched().link &&
  !!formApi.getError().link

const CreateLink = ({ post, changePost }) => {
  return (
    <Form
      validateError={errorValidator}
      validateSuccess={successValidator}
      onSubmit={values => {
        changePost(values, 'title')
      }}
    >
      {formApi => (
        <form
          className='event-posts-new-step'
          onSubmit={formApi.submitForm}
          autoComplete='off'
        >
          <label>Link</label>
          <ReactFormInput
            fluid
            autoFocus
            initvalue={post.link}
            field='link'
            error={isError(formApi)}
            placeholder='Paster a URL (e.g. https://twitter/insight)'
          />
          {isError(formApi) && (
            <Message negative>{formApi.getError().link}</Message>
          )}
          <div className='event-posts-step-control event-posts-step-control_right'>
            <Button
              disabled={!!formApi.getError().link}
              positive={!!formApi.getSuccess().link}
              type='submit'
            >
              Next
            </Button>
          </div>
        </form>
      )}
    </Form>
  )
}

export default CreateLink
