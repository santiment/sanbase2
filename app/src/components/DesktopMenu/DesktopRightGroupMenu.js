import React from 'react'
import { Button } from 'semantic-ui-react'
import { connect } from 'react-redux'
import { branch, renderComponent, compose } from 'recompose'
import { NavLink } from 'react-router-dom'
import { checkIsLoggedIn } from './../../pages/UserSelectors'
import * as actions from './../../actions/types'
import FeedbackButton from './../FeedbackButton/FeedbackButton'
import SmoothDropdownItem from './../SmoothDropdown/SmoothDropdownItem'
import DesktopProfileMenu from './DesktopProfileMenu'
import Guide from './../Guide/Guide'
import styles from './../FeedbackButton/FeedbackButton.module.css'
import './DesktopRightGroupMenu.css'

const HiddenElement = () => ''

const AnonymDesktopRightGroupMenu = () => (
  <div className='user-auth-control'>
    <FeedbackButton />
    <NavLink to='/login'>Login</NavLink>
  </div>
)

const displayLoggedIn = branch(
  ({ isLoggedIn }) => !isLoggedIn,
  renderComponent(AnonymDesktopRightGroupMenu)
)

const DesktopRightGroupMenu = ({
  balance,
  logout,
  toggleNightMode,
  toggleBetaMode,
  isNightModeEnabled,
  isBetaModeEnabled
}) => (
  <div className='user-auth-control'>
    <HiddenElement>
      <SmoothDropdownItem
        trigger={
          <Button className={styles.feedbackButton} circular icon='book' />
        }
        id='guide'
      >
        <Guide />
      </SmoothDropdownItem>
    </HiddenElement>
    <FeedbackButton />
    <SmoothDropdownItem trigger={<Button circular icon='user' />} id='profile'>
      <DesktopProfileMenu
        balance={balance}
        logout={logout}
        toggleNightMode={toggleNightMode}
        toggleBetaMode={toggleBetaMode}
        isNightModeEnabled={isNightModeEnabled}
        isBetaModeEnabled={isBetaModeEnabled}
      />
    </SmoothDropdownItem>
  </div>
)

const mapStateToProps = state => ({
  balance: state.user.data.sanBalance,
  isLoggedIn: checkIsLoggedIn(state),
  isNightModeEnabled: state.rootUi.isNightModeEnabled,
  isBetaModeEnabled: state.rootUi.isBetaModeEnabled
})

const mapDispatchToProps = dispatch => ({
  logout: () => {
    dispatch({
      type: actions.USER_LOGOUT_SUCCESS
    })
  },
  toggleNightMode: () => {
    dispatch({
      type: actions.USER_TOGGLE_NIGHT_MODE
    })
  },
  toggleBetaMode: () => {
    dispatch({
      type: actions.USER_TOGGLE_BETA_MODE
    })
  }
})

export default compose(
  connect(
    mapStateToProps,
    mapDispatchToProps
  ),
  displayLoggedIn
)(DesktopRightGroupMenu)
