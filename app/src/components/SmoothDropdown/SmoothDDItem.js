import React, { Component } from 'react'

export class SmoothDDItem extends Component {
  render () {
    const { trigger, children } = this.props
    // const { current: dropdown } = this.myRef
    // const { current: triggerRef } = this.triggerRef

    console.log(this.myRef)
    createDrop(trigger, dropdown)
    return (
      <SmoothDropdownContext.Consumer>
        {({ portal, changeDrop, hideDrop, activeTrigger }) => (
          <Fragment>
            {/* {console.log(portal)} */}
            <div
              onMouseEnter={() => changeDrop(trigger)}
              onMouseLeave={hideDrop}
              className={`${trigger === activeTrigger ? 'active' : ''}`}
            >
              {trigger}
            </div>
            {portal &&
              ReactDOM.createPortal(
                <div
                  className={`dd__item dropdown-menu ${
                    trigger === activeTrigger ? 'active' : ''
                  }`}
                >
                  <div className='dd__content dropdown-menu__content'>
                    {children}
                  </div>
                </div>,
                portal
              )}
          </Fragment>
        )}
      </SmoothDropdownContext.Consumer>
    )
  }
}

export default SmoothDDItem
