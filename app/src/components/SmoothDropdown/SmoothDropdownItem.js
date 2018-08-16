import React, { Component, Fragment } from 'react'
import ReactDOM from 'react-dom'
import { SmoothDropdownContext, createDrop } from './SmoothDropdown'

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

export class SmoothDropdownItem extends Component {
  myRef = React.createRef()
  triggerRef = React.createRef()

  render () {
    const { trigger, children } = this.props
    const { current: dropdown } = this.myRef
    const { current: triggerRef } = this.triggerRef
    const child = (
      <li className='dropdown smooth-dropdown__item' ref={this.myRef}>
        <div className='content'>{children}</div>
      </li>
    )
    console.log(this.myRef)
    createDrop(triggerRef, dropdown)
    return (
      <SmoothDropdownContext.Consumer>
        {({ portal, changeDrop, hideDrop }) => (
          <Fragment>
            {/* {console.log(portal)} */}
            <div
              onMouseEnter={() => changeDrop(triggerRef)}
              onMouseLeave={hideDrop}
              ref={this.triggerRef}
            >
              {trigger}
            </div>
            {portal && ReactDOM.createPortal(child, portal)}
          </Fragment>
        )}
      </SmoothDropdownContext.Consumer>
    )
  }
}

// const SmoothDropdownItem = ({ trigger, children, id }) => {
//   const child = (
//     <li className='dropdown smooth-dropdown__item' data-id={id}>
//       {children}
//     </li>
//   )
//   console.log(child)
//   createDrop(trigger, child)
//   return (
//     <SmoothDropdownContext.Consumer>
//       {({ portal, changeDrop }) => (
//         <Fragment>
//           {/* {console.log(portal)} */}
//           <div onMouseEnter={() => changeDrop(trigger)} data-id={id}>
//             {trigger}
//           </div>
//           {portal && ReactDOM.createPortal(child, portal)}
//         </Fragment>
//       )}
//     </SmoothDropdownContext.Consumer>
//   )
// }

export default SmoothDropdownItem
