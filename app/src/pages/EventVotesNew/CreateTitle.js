import React from 'react'
import {
  Button,
  Message
} from 'semantic-ui-react'
import { Form } from 'react-form'
import ReactFormInput from '../../components/react-form-semantic-ui-react/ReactFormInput'
import TagsField from './TagsField'

const TITLE_MAX_LENGTH = 140

const errorValidator = ({title}) => ({
  title: !title || title.length < 3 || title.length > TITLE_MAX_LENGTH ? 'Short description should be normal' : null
})

const successValidator = ({title}) => ({
  title: title && title.length > 3 && title.length <= TITLE_MAX_LENGTH ? 'Thank you for entering short description' : null
})

const isError = formApi => (
  !!formApi.getValue().title &&
    formApi.getTouched().title &&
    !!formApi.getError().title
)

const LimitSizeOfTitle = ({length}) => (
  <small>
    &nbsp;{TITLE_MAX_LENGTH - length} | Max length is {TITLE_MAX_LENGTH}
  </small>
)

const CreateTitle = ({post, changePost}) => {
  return (
    <Form
      validateError={errorValidator}
      validateSuccess={successValidator}
      onSubmit={values => {
        console.log(values)
        changePost(values, 'confirm')
      }}>
      {formApi => (<form
        className='event-posts-new-step'
        onSubmit={formApi.submitForm}
        autoComplete='off'>
        <label>Short description (required)
          {formApi.values.title &&
            formApi.values.title.length > TITLE_MAX_LENGTH &&
            <LimitSizeOfTitle
              length={formApi.values.title ? formApi.values.title.length : 0} />}
        </label>
        <ReactFormInput
          fluid
          autoFocus
          initvalue={post.title}
          field='title'
          error={isError(formApi)}
          placeholder='Add a short description' />
        {isError(formApi) &&
          <Message negative>
            {formApi.getError().title}
          </Message>}
        <TagsField setTags={tags => {
          formApi.values.tags = tags
        }} />
        <br />
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
