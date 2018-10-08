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
import './DesktopRightGroupMenu.css'

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
  isNightModeEnabled
}) => (
  <div className='user-auth-control'>
    <FeedbackButton />
    <SmoothDropdownItem trigger={<Button circular icon='user' />} id='profile'>
      <DesktopProfileMenu
        balance={balance}
        logout={logout}
        toggleNightMode={toggleNightMode}
        isNightModeEnabled={isNightModeEnabled}
      />
    </SmoothDropdownItem>
  </div>
)

const mapStateToProps = state => ({
  balance: state.user.data.sanBalance,
  isLoggedIn: checkIsLoggedIn(state),
  isNightModeEnabled: state.rootUi.isNightModeEnabled
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
  }
})

export default compose(
  connect(mapStateToProps, mapDispatchToProps),
  displayLoggedIn
)(DesktopRightGroupMenu)
