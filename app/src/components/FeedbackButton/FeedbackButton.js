import React from 'react'
import { compose } from 'recompose'
import { connect } from 'react-redux'
import { Button } from 'semantic-ui-react'
import SmoothDropdownItem from './../SmoothDropdown/SmoothDropdownItem'
import styles from './FeedbackButton.module.css'

export const FeedbackButton = ({ toggleFeedback, ...props }) => (
  <SmoothDropdownItem
    trigger={
      <Button
        className={styles.feedbackButton}
        onClick={toggleFeedback}
        circular
        icon='comments'
      />
    }
    id='feedback'
  >
    <p className={styles.helpMessage}>Send a feedback</p>
  </SmoothDropdownItem>
)

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

export default enhance(FeedbackButton)
