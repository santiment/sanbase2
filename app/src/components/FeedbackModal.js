import React from 'react'
import Raven from 'raven-js'
import axios from 'axios'
import {
  Button,
  Modal,
  TextArea,
  Form,
  Message
} from 'semantic-ui-react'
import { connect } from 'react-redux'
import { compose, withState } from 'recompose'
import { FadeIn } from 'animate-components'
import './FeedbackModal.css'

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

const FeedbackModal = ({
  isFeedbackModalOpened,
  toggleFeedback,
  ...props
}) => {
  return (
    <Modal
      open={isFeedbackModalOpened}
      dimmer={'blurring'}
      onClose={() => {
        props.onChange('')
        props.onSuccess(false)
        props.onError(false)
        props.onPending(false)
      }}
      className='feedback-modal'>
      <Modal.Content>
        <FadeIn duration='0.5s' timingFunction='ease-out' as='div'>
          {props.isSuccess
          ? 'Thank you!'
          : <Form
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
            {props.message.length >= MAX_FEEDBACK_MESSAGE_LENGTH - 1 &&
            <Message attached='bottom' warning>
              Maximum length of feedback message.
            </Message>}
          </Form>}
        </FadeIn>
      </Modal.Content>
      <Modal.Actions>
        <Button basic onClick={toggleFeedback}>
          Close
        </Button>
        {!props.isSuccess &&
          <Button
            basic
            size='tiny'
            color='green'
            onClick={() => {
              !props.isPending && handleSendFeedback(props)
            }}>
            {props.isPending ? 'Waiting...' : 'Submit'}
          </Button>}
      </Modal.Actions>
    </Modal>
  )
}

const mapStateToProps = state => {
  return {
    isFeedbackModalOpened: state.rootUi.isFeedbackModalOpened
  }
}

const mapDispatchToProps = dispatch => {
  return {
    toggleFeedback: () => {
      dispatch({
        type: 'TOGGLE_FEEDBACK_MODAL'
      })
    }
  }
}

const enhance = compose(
  withState('isPending', 'onPending', false),
  withState('message', 'onChange', ''),
  withState('isSuccess', 'onSuccess', false),
  withState('isError', 'onError', false),
  connect(mapStateToProps, mapDispatchToProps)
)

export default enhance(FeedbackModal)
