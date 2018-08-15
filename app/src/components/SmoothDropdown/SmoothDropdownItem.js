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

  render () {
    const { trigger, children } = this.props
    const child = (
      <li className='dropdown smooth-dropdown__item' ref={this.myRef}>
        {children}
      </li>
    )
    console.log(this.myRef)
    createDrop(trigger, this.myRef.current)
    return (
      <SmoothDropdownContext.Consumer>
        {({ portal, changeDrop }) => (
          <Fragment>
            {/* {console.log(portal)} */}
            <div onMouseEnter={() => changeDrop(trigger)}>{trigger}</div>
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
