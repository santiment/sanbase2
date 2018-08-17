import React, { Component, Fragment } from 'react'
import ReactDOM from 'react-dom'
import { SmoothDdContext, createDrop } from './SmoothDD'

export class SmoothDDItem extends Component {
  dropdownRef = React.createRef()
  triggerRef = React.createRef()

  render () {
    const { trigger, children, id } = this.props
    const {
      triggerRef: { current: ddTrigger },
      dropdownRef: { current: ddDropdown }
    } = this
    // const { current: dropdown } = this.myRef
    // const { current: triggerRef } = this.triggerRef

    // console.log(ddDropdown, this.dropdownRef)
    createDrop(ddTrigger, ddDropdown)
    return (
      <SmoothDdContext.Consumer>
        {({
          portal,
          handleMouseEnter,
          handleMouseLeave,
          currentTrigger,
          startCloseTimeout,
          stopCloseTimeout
        }) => (
          <Fragment>
            {/* {console.log(portal)} */}
            <div
              onMouseEnter={() => {
                // console.log(ddTrigger)
                handleMouseEnter(ddTrigger)
              }}
              onMouseLeave={handleMouseLeave}
              className={`dd__trigger ${
                ddTrigger === currentTrigger ? 'active' : ''
              }`}
              ref={this.triggerRef}
            >
              {trigger}
            </div>
            {portal &&
              ReactDOM.createPortal(
                <div
                  id={id}
                  className={`dd__item dd-dropdown-menu ${
                    ddTrigger === currentTrigger ? 'active' : ''
                  }`}
                  ref={this.dropdownRef}
                >
                  <div
                    className='dd__content dropdown-menu__content'
                    onMouseEnter={stopCloseTimeout}
                    onMouseLeave={startCloseTimeout}
                  >
                    {children}
                  </div>
                </div>,
                portal
              )}
          </Fragment>
        )}
      </SmoothDdContext.Consumer>
    )
  }
}

export default SmoothDDItem
