import React, { Fragment } from 'react'
import ReactDOM from 'react-dom'
import { SmoothDropdownContext } from './SmoothDropdown'

// const SmoothDropdownItem = ({ trigger, children, id }) => {
//   const child = (
//     <li className='dropdown smooth-dropdown__item' data-id={id}>{children}</li>
//   )
//   return (
//     <Fragment>
//       <div
//         onMouseEnter={evt => console.log(evt.currentTarget.dataset.id)}
//         data-id={id}
//       >
//         {trigger}
//       </div>
//       <SmoothDropdownContext.Consumer>
//         {portal => ReactDOM.createPortal(child, portal)}
//       </SmoothDropdownContext.Consumer>
//     </Fragment>
//   )
// }
const SmoothDropdownItem = ({ trigger, children, id }) => {
  const child = (
    <li className='dropdown smooth-dropdown__item' data-id={id}>
      {children}
    </li>
  )
  return (
    <SmoothDropdownContext.Consumer>
      {({ portal, changeDrop }) => (
        <Fragment>
          {console.log(portal)}
          <div onMouseEnter={() => changeDrop(id)} data-id={id}>
            {trigger}
          </div>
          {portal && ReactDOM.createPortal(child, portal)}
        </Fragment>
      )}
    </SmoothDropdownContext.Consumer>
  )
}

export default SmoothDropdownItem
