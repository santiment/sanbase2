import React, { Fragment } from 'react'
import ReactDOM from 'react-dom'
import { SmoothDropdownContext } from './SmoothDropdown'

const SmoothDropdownItem = ({ trigger, children }) => {
  const child = <li className='dropdown smooth-dropdown__item'>{children}</li>
  return (
    <Fragment>
      <div onMouseEnter={evt => console.log(evt)}>{trigger}</div>
      <SmoothDropdownContext.Consumer>
        {portal => ReactDOM.createPortal(child, portal)}
      </SmoothDropdownContext.Consumer>
    </Fragment>
  )
}

export default SmoothDropdownItem
