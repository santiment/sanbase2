import React from 'react'
import { compose } from 'recompose'
import { connect } from 'react-redux'
import { Button } from 'semantic-ui-react'
import SmoothDropdownItem from './SmoothDropdown/SmoothDropdownItem'

const FeedbackBtn = ({ toggleFeedback, ...props }) => {
  return (
    <div className='feedback-button-wrapper'>
      <SmoothDropdownItem
        className='feedback-body-wrapper'
        trigger={<Button onClick={toggleFeedback} circular icon='bullhorn' />}
      >
        Send a feedback
      </SmoothDropdownItem>
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

const enhance = compose(connect(undefined, mapDispatchToProps))

export default enhance(FeedbackBtn)
