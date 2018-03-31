import React from 'react'
import Raven from 'raven-js'
import axios from 'axios'
import { compose, withState } from 'recompose'
import { FadeIn } from 'animate-components'
import {
  Button,
  Popup,
  Icon,
  TextArea,
  Form
} from 'semantic-ui-react'

const handleSendFeedback = ({message = '', onPending, onSuccess, onError}) => {
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
    Raven.captureException('Alert about new insight ' + JSON.stringify(error))
  }
}

const FeedbackBtn = props => {
  return (
    <div
      className='feedback-button-wrapper'>
      <Popup
        className='feedback-body-wrapper'
        basic
        wide
        trigger={
          <Button size='tiny'>
            <Icon name='bullhorn' />
            Feedback about this page?
          </Button>
      } on='click'>
        <FadeIn duration='0.5s' timingFunction='ease-out' as='div'>
          <Form onSubmit={() => handleSendFeedback(props)}>
            <TextArea
              onChange={e => props.onChange(e.target.value)}
              autoHeight placeholder='Start typing...' />
            {props.isSuccess
              ? <div>Thank you!</div>
              : <Button type='submit' basic size='tiny' color='green'>
                {props.isPending ? 'Waiting...' : 'Submit'}
              </Button>}
          </Form>
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
