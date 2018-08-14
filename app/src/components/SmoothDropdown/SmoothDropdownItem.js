import React from 'react'
import ReactDOM from 'react-dom'
import { SmoothDropdownContext } from './SmoothDropdown'

const SmoothDropdownItem = ({ children }) => (
  <SmoothDropdownContext.Consumer>
    {portal => ReactDOM.createPortal(children, portal)}
  </SmoothDropdownContext.Consumer>
)

export default SmoothDropdownItem
