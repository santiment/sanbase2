import React from 'react'
import Raven from 'raven-js'
import axios from 'axios'
import { compose, withState } from 'recompose'
import { FadeIn } from 'animate-components'
import {
  Button,
  Popup,
  TextArea,
  Form,
  Message
} from 'semantic-ui-react'

const MAX_FEEDBACK_MESSAGE_LENGTH = 320

const handleSendFeedback = ({message = '', onPending, onSuccess, onError}) => {
  if (message.length > MAX_FEEDBACK_MESSAGE_LENGTH) { return }
  try {
    onPending(true)
    axios({
      method: 'post',
      url: 'https://us-central1-cryptofolio-15d92.cloudfunctions.net/feedback',
      data: { message }
    }).then(res => {
      onPending(false)
      onSuccess(true)
    })
  } catch (error) {
    onPending(false)
    onError(true)
    Raven.captureException('Feedback form has an error: ' + JSON.stringify(error))
  }
}

const FeedbackBtn = props => {
  return (
    <div className='feedback-button-wrapper'>
      <Popup
        className='feedback-body-wrapper'
        basic
        inverted
        position='bottom center'
        wide
        onClose={() => {
          props.onChange('')
          props.onSuccess(false)
          props.onError(false)
          props.onPending(false)
        }}
        trigger={
          <Button circular icon='bullhorn' />
      } on='hover'>
        <FadeIn duration='0.5s' timingFunction='ease-out' as='div'>
          <Form
            className='attached fluid'
            onSubmit={() => handleSendFeedback(props)}>
            <TextArea
              value={props.message}
              onChange={e => {
                const message = e.target.value
                if (message.length < MAX_FEEDBACK_MESSAGE_LENGTH) {
                  props.onChange(e.target.value)
                }
              }}
              autoHeight placeholder='Start typing...' />
            {props.isSuccess
              ? <div>Thank you!</div>
              : <Button type='submit' basic size='tiny' color='green'>
                {props.isPending ? 'Waiting...' : 'Submit'}
              </Button>}
          </Form>
          {props.message.length >= MAX_FEEDBACK_MESSAGE_LENGTH - 1 &&
          <Message attached='bottom' warning>
            Maximum length of feedback message.
          </Message>}
        </FadeIn>
      </Popup>
    </div>
  )
}

const enhance = compose(
  withState('isPending', 'onPending', false),
  withState('message', 'onChange', ''),
  withState('isSuccess', 'onSuccess', false),
  withState('isError', 'onError', false)
)

export default enhance(FeedbackBtn)
