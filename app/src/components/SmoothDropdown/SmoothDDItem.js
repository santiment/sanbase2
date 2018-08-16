import React, { Component, Fragment } from 'react'
import ReactDOM from 'react-dom'
import { SmoothDdContext, createDrop } from './SmoothDD'

export class SmoothDDItem extends Component {
  dropdownRef = React.createRef()

  render () {
    const { trigger, children } = this.props
    // const { current: dropdown } = this.myRef
    // const { current: triggerRef } = this.triggerRef

    // console.log(this.myRef)
    createDrop(trigger, this.dropdownRef)
    return (
      <SmoothDdContext.Consumer>
        {({ portal, handleMouseEnter, handleMouseLeave, currentTrigger }) => (
          <Fragment>
            {/* {console.log(portal)} */}
            <div
              onMouseEnter={() => {
                console.log(portal, currentTrigger, handleMouseEnter)
                handleMouseEnter(trigger)
              }}
              onMouseLeave={handleMouseLeave}
              className={`${trigger === currentTrigger ? 'active' : ''}`}
            >
              {trigger}
            </div>
            {portal &&
              ReactDOM.createPortal(
                <div
                  className={`dd__item dropdown-menu ${
                    trigger === currentTrigger ? 'active' : ''
                  }`}
                  ref={this.dropdownRef}
                >
                  <div className='dd__content dropdown-menu__content'>
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
