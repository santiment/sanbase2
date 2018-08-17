import React, { Component, Fragment } from 'react'
import './SmoothDropdown.css'

export const SmoothDdContext = React.createContext({
  portal: document.createElement('div'),
  currentTrigger: null,
  handleMouseEnter: trigger => {},
  handleMouseLeave: () => {}
})

const dropdowns = new WeakMap()

export const createDrop = (trigger, dropdown) =>
  trigger && dropdowns.set(trigger, dropdown)

export class SmoothDD extends Component {
  portalRef = React.createRef()

  state = {
    currentTrigger: null,
    dropdownStyles: {}
  }

  startCloseTimeout = () =>
    (this.dropdownTimer = setTimeout(() => this.closeDropdown(), 150))

  stopCloseTimeout = () => clearTimeout(this.dropdownTimer)

  openDropdown = trigger => {
    // if (dropdowns.has(trigger)) {
    //   this.setState(prevState => ({
    //     ...prevState,
    //     currentTrigger: trigger
    //   }))
    // }
    // const { currentTrigger } = this.state

    const dropdown = dropdowns.get(trigger)
    if (!dropdown) return
    const triggerMeta = trigger.getBoundingClientRect()
    const ddMeta = dropdown.firstElementChild.getBoundingClientRect()

    // ddList.style.opacity = 1
    // ddList.style.left =
    //   triggerMeta.left - (ddMeta.width / 2 - triggerMeta.width / 2) + 'px'
    const left =
      triggerMeta.left - (ddMeta.width / 2 - triggerMeta.width / 2) + 'px'
    const width = ddMeta.width + 'px'
    const height = ddMeta.height + 'px'

    console.table({ dropdown: dropdown.id, width, height })

    this.setState(prevState => ({
      ...prevState,
      currentTrigger: trigger,
      dropdownStyles: {
        left,
        width,
        height
      }
    }))
  }

  closeDropdown = () => {
    this.setState(prevState => ({
      ...prevState,
      currentTrigger: null
    }))
  }

  handleMouseEnter = trigger => {
    if (!trigger) return
    this.stopCloseTimeout()
    this.openDropdown(trigger)
  }

  handleMouseLeave = () => this.startCloseTimeout()

  render () {
    const { children } = this.props
    const { currentTrigger, dropdownStyles } = this.state
    const {
      portalRef,
      handleMouseEnter,
      handleMouseLeave,
      startCloseTimeout,
      stopCloseTimeout
    } = this
    return (
      <SmoothDdContext.Provider
        value={{
          portal: portalRef.current,
          currentTrigger,
          handleMouseEnter,
          handleMouseLeave,
          startCloseTimeout,
          stopCloseTimeout
        }}
      >
        {children('tester')}
        <div
          className={`dd dropdown-holder ${
            currentTrigger ? 'has-dropdown-active' : ''
          }`}
        >
          <div
            className='dd__list dropdown__wrap'
            style={dropdownStyles}
            ref={portalRef}
          />
          <div className='dd__arrow dropdown__arrow' />
          <div className='dd__bg dropdown__bg' style={dropdownStyles} />
        </div>
      </SmoothDdContext.Provider>
    )
  }
}

export default SmoothDD
