import React, { Fragment } from 'react'
import ReactDOM from 'react-dom'
import { SmoothDropdownContext } from './SmoothDropdown'

const SmoothDropdownItem = ({ trigger, children }) => (
  <Fragment>
    <div onMouseEnter={evt => console.log(evt)}>{trigger}</div>
    <SmoothDropdownContext.Consumer>
      {portal => ReactDOM.createPortal(children, portal)}
    </SmoothDropdownContext.Consumer>
  </Fragment>
)

export default SmoothDropdownItem
