import React from 'react'
import { withState } from 'recompose'
import { Icon } from 'semantic-ui-react'
import './FloatingButton.css'

const FloatingButton = ({ isToggled = false, toggle, handleSearchClick }) => (
  <div className='floating-btn-container'>
    <div
      onClick={e => {
        e.preventDefault()
        toggle(!isToggled)
        handleSearchClick()
      }}
      className={
        isToggled ? 'floating-btn floating-btn--rotation' : 'floating-btn'
      }
    >
      <Icon size='large' name={isToggled ? 'remove' : 'search'} />
    </div>
  </div>
)

export default withState('isToggled', 'toggle', false)(FloatingButton)
