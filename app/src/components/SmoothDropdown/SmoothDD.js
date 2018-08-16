import React, { Component, Fragment } from 'react'

export const SmoothDropdownContext = React.createContext({
  portal: document.createElement('ul'),
  currentTrigger: null,
  changeDrop: id => {},
  hideDrop: () => {}
})

const dropdowns = new WeakMap()

export const createDrop = (trigger, dropdown) =>
  trigger && dropdowns.set(trigger, dropdown)

export class SmoothDD extends Component {
  portalRef = React.createRef()

  render () {
    const { children } = this.props
    return (
      <Fragment>
        {children}
        <div className='dd dropdown-holder'>
          <div class='dd__arrow dropdown__arrow' />
          <div class='dd__bg dropdown__bg' />
          <SmoothDropdownContext.Provider
            value={{
              portal: this.portalRef.current
            }}
          >
            <div className='dd__list dropdown__wrap' ref={this.portalRef} />
          </SmoothDropdownContext.Provider>
        </div>
      </Fragment>
    )
  }
}

export default SmoothDD
