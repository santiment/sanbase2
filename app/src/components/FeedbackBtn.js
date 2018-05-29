import React from 'react'
import { compose } from 'recompose'
import { connect } from 'react-redux'
import { Button, Popup } from 'semantic-ui-react'

const FeedbackBtn = ({toggleFeedback, ...props}) => {
  return (
    <div className='feedback-button-wrapper'>
      <Popup
        className='feedback-body-wrapper'
        basic
        inverted
        position='bottom center'
        wide
        trigger={
          <Button onClick={toggleFeedback} circular icon='bullhorn' />
      } on='hover'>
        Send a feedback
      </Popup>
    </div>
  )
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
  connect(
    undefined,
    mapDispatchToProps
  )
)

export default enhance(FeedbackBtn)
