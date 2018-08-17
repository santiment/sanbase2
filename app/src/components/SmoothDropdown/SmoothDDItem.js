// import React, { Component, Fragment } from 'react'
// import ReactDOM from 'react-dom'
// import { SmoothDropdownContext } from './SmoothDD'

// export class SmoothDropdownItem extends Component {
//   dropdownRef = React.createRef()
//   triggerRef = React.createRef()

//   componentDidMount () {
//     setTimeout(() => this.forceUpdate(), 100) // VERY HACKY - NECESSARY TO UPDATE DROPDOWN IN DOM
//   }

//   render () {
//     const { trigger, children, id } = this.props
//     const {
//       triggerRef: { current: ddTrigger },
//       dropdownRef: { current: ddDropdown }
//     } = this

//     return (
//       <SmoothDropdownContext.Consumer>
//         {({
//           portal,
//           handleMouseEnter,
//           handleMouseLeave,
//           currentTrigger,
//           startCloseTimeout,
//           stopCloseTimeout
//         }) => (
//           <Fragment>
//             <div
//               onMouseEnter={() => {
//                 // console.log(`Mouse entered on #${id}`)
//                 // console.dir(ddDropdown)
//                 handleMouseEnter(ddTrigger, ddDropdown)
//               }}
//               onMouseLeave={handleMouseLeave}
//               className={`dd__trigger ${ddTrigger === currentTrigger ? 'active' : ''}`}
//               ref={this.triggerRef}
//             >
//               {trigger}
//             </div>
//             {ReactDOM.createPortal(
//               <div
//                 id={id}
//                 className={`dd__item dd-dropdown-menu ${ddTrigger === currentTrigger ? 'active' : ''}`}
//                 ref={this.dropdownRef}
//               >
//                 <div
//                   className='dd__content dropdown-menu__content'
//                   onMouseEnter={stopCloseTimeout}
//                   onMouseLeave={startCloseTimeout}
//                 >
//                   {children}
//                 </div>
//               </div>,
//               portal
//             )}
//           </Fragment>
//         )}
//       </SmoothDropdownContext.Consumer>
//     )
//   }
// }

// export default SmoothDropdownItem
