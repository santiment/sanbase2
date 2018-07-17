import React from 'react'
import { Link } from 'react-router-dom'
import { Button, Modal, Checkbox, Header, Form } from 'semantic-ui-react'
import { connect } from 'react-redux'
import { compose, withState } from 'recompose'
import { FadeIn } from 'animate-components'
import * as actions from './../actions/types'

const GDPRModal = ({
  isGDPRModalOpened,
  toggleGDPRModal,
  isGDPRChecked,
  setGDPRChecked,
  togglePrivacyPolicy
}) => (
  <Modal
    open={isGDPRModalOpened}
    dimmer={'blurring'}
    className='feedback-modal'
  >
    <Header icon='law' content='Santiment are now GDPR-ready!' />
    <Modal.Content>
      <FadeIn duration='0.5s' timingFunction='ease-out' as='div'>
        <Form className='attached fluid' onSubmit={() => console.log('send')}>
          <p>
            Please accept our updated Privacy Policy by May, 2018 to continue
            using Sanbase
          </p>
          <Checkbox
            checked={isGDPRChecked}
            onClick={() => setGDPRChecked(!isGDPRChecked)}
            label={<label>I have read and accept the &nbsp;</label>}
          />
          <Link onClick={toggleGDPRModal} to='/privacy-policy'>
            Santiment Privacy Policy
          </Link>
        </Form>
      </FadeIn>
    </Modal.Content>
    <Modal.Actions>
      <Button
        disabled={!isGDPRChecked}
        basic
        onClick={() => togglePrivacyPolicy()}
      >
        I Agree
      </Button>
    </Modal.Actions>
  </Modal>
)

const mapStateToProps = state => {
  return {
    isGDPRModalOpened: state.rootUi.isGDPRModalOpened
  }
}

const mapDispatchToProps = (dispatch, ownProps) => {
  return {
    toggleGDPRModal: () => {
      ownProps.setGDPRChecked(false)
      dispatch({
        type: actions.APP_TOGGLE_GDPR_MODAL
      })
    },
    togglePrivacyPolicy: () => {
      ownProps.setGDPRChecked(false)
      dispatch({ type: actions.USER_TOGGLE_PRIVACY_POLICY })
    }
  }
}

const enhance = compose(
  withState('isGDPRChecked', 'setGDPRChecked', false),
  connect(mapStateToProps, mapDispatchToProps)
)

export default enhance(GDPRModal)
