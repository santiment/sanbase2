import React, { Component } from 'react'
import cx from 'classnames'
import './SmoothDropdown.css'

export const SmoothDropdownContext = React.createContext({
  portal: {},
  currentTrigger: null,
  handleMouseEnter: trigger => {},
  handleMouseLeave: () => {},
  startCloseTimeout: () => {},
  stopCloseTimeout: () => {}
})

export class SmoothDropdown extends Component {
  portalRef = React.createRef()

  state = {
    portalMounted: false,
    currentTrigger: null,
    ddFirstTime: false,
    dropdownStyles: {}
  }

  componentDidMount () {
    if (this.state.portalMounted === false) {
      this.setState(prevState => ({
        ...prevState,
        portalMounted: true
      })) // HACK TO POPULATE PORTAL AND UPDATE REFS
    }
  }

  startCloseTimeout = () =>
    (this.dropdownTimer = setTimeout(() => this.closeDropdown(), 150))

  stopCloseTimeout = () => clearTimeout(this.dropdownTimer)

  openDropdown = (trigger, dropdown) => {
    const triggerMeta = trigger.getBoundingClientRect()
    const ddMeta = dropdown.firstElementChild.getBoundingClientRect()

    // console.log(dropdown.offsetLeft, ddMeta.left)
    // console.log(triggerMeta, ddMeta)

    const left =
      triggerMeta.left - (ddMeta.width / 2 - triggerMeta.width / 2) + 'px'
    const width = ddMeta.width + 'px'
    const height = ddMeta.height + 'px'

    this.setState(prevState => ({
      ...prevState,
      currentTrigger: trigger,
      ddFirstTime: prevState.currentTrigger === null,
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

  handleMouseEnter = (trigger, dropdown) => {
    this.stopCloseTimeout()
    this.openDropdown(trigger, dropdown)
  }

  handleMouseLeave = () => this.startCloseTimeout()

  render () {
    const { children } = this.props
    const { currentTrigger, dropdownStyles, ddFirstTime } = this.state
    const {
      portalRef,
      handleMouseEnter,
      handleMouseLeave,
      startCloseTimeout,
      stopCloseTimeout
    } = this
    return (
      <SmoothDropdownContext.Provider
        value={{
          portal: portalRef.current || document.createElement('ul'),
          currentTrigger,
          handleMouseEnter,
          handleMouseLeave,
          startCloseTimeout,
          stopCloseTimeout
        }}
      >
        {children}
        <div
          style={dropdownStyles}
          className={cx({
            dd: true,
            'has-dropdown-active': currentTrigger !== null,
            'dd-first-time': ddFirstTime
          })}
        >
          <div className='dd__list' id='dd-portal' ref={portalRef} />
          <div className='dd__arrow' />
          <div className='dd__bg' />
        </div>
      </SmoothDropdownContext.Provider>
    )
  }
}

export default SmoothDropdown
