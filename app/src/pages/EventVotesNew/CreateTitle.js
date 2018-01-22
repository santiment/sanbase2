import React from 'react'
import {
  Button,
  Message
} from 'semantic-ui-react'
import { Form } from 'react-form'
import ReactFormInput from '../../components/react-form-semantic-ui-react/ReactFormInput'

const errorValidator = ({title}) => ({
  title: !title || title.length < 3 ? 'Title should be normal' : null
})

const successValidator = ({title}) => ({
  title: title && title.length > 3 ? 'Thank you for entering title' : null
})

const isError = formApi => (
  !!formApi.getValue().title &&
    formApi.getTouched().title &&
    !!formApi.getError().title
)

const CreateTitle = ({post, changePost}) => {
  return (
    <Form
      validateError={errorValidator}
      validateSuccess={successValidator}
      onSubmit={values => {
        changePost(values, 'confirm')
      }}>
      {formApi => (<form
        className='event-posts-new-step'
        onSubmit={formApi.submitForm}
        autoComplete='off'>
        <label>Title</label>
        <ReactFormInput
          fluid
          autoFocus
          initvalue={post.title}
          field='title'
          error={isError(formApi)}
          placeholder='Add a title' />
        {isError(formApi) &&
          <Message negative>
            {formApi.getError().title}
          </Message>}
        <div className='event-posts-new-step-control'>
          <Button
            disabled={!formApi.getSuccess().title}
            positive={!!formApi.getSuccess().title}
            type='submit'>
            Next
          </Button>
        </div>
      </form>)}
    </Form>
  )
}

export default CreateTitle
