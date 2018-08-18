import React, { Component } from 'react'
import cx from 'classnames'
import './SmoothDropdown.css'

export const ddAsyncUpdateTimeout = 99

export const SmoothDropdownContext = React.createContext({
  portal: {},
  currentTrigger: null,
  handleMouseEnter: () => {},
  handleMouseLeave: () => {},
  startCloseTimeout: () => {},
  stopCloseTimeout: () => {}
})

class SmoothDropdown extends Component {
  portalRef = React.createRef()

  state = {
    currentTrigger: null,
    ddFirstTime: false,
    arrowCorrectionX: 0,
    dropdownStyles: {}
  }

  componentDidMount () {
    setTimeout(() => this.forceUpdate(), ddAsyncUpdateTimeout) // HACK TO POPULATE PORTAL AND UPDATE REFS
  }

  startCloseTimeout = () =>
    (this.dropdownTimer = setTimeout(() => this.closeDropdown(), 150))

  stopCloseTimeout = () => clearTimeout(this.dropdownTimer)

  handleMouseEnter = (trigger, dropdown) => {
    this.stopCloseTimeout()
    this.openDropdown(trigger, dropdown)
  }

  handleMouseLeave = () => this.startCloseTimeout()

  openDropdown = (trigger, dropdown) => {
    if (!dropdown) return

    const ddContent = dropdown.querySelector('.dd__content')

    const leftOffset =
      trigger.offsetLeft - (ddContent.clientWidth - trigger.clientWidth) / 2

    const correction = this.correctViewportOverflow(trigger, ddContent)

    const left = leftOffset - correction.left + 'px'
    const width = ddContent.clientWidth + 'px'
    const height = ddContent.clientHeight + 'px'

    this.setState(prevState => ({
      ...prevState,
      currentTrigger: trigger,
      ddFirstTime: prevState.currentTrigger === null,
      dropdownStyles: {
        left,
        width,
        height
      },
      arrowCorrectionX: correction.left
    }))
  }

  closeDropdown = () => {
    this.setState(prevState => ({
      ...prevState,
      currentTrigger: null
    }))
  }

  correctViewportOverflow (trigger, ddContent) {
    const correction = { left: 0 }
    const triggerViewport = trigger.getBoundingClientRect()

    const ddLeftCornerX =
      triggerViewport.left - (ddContent.clientWidth - triggerViewport.width) / 2
    const ddRightCornerX = ddLeftCornerX + ddContent.clientWidth

    if (ddRightCornerX > window.innerWidth) {
      correction.left = ddRightCornerX - window.innerWidth
    } else if (ddLeftCornerX < 0) {
      correction.left = ddLeftCornerX
    }

    return correction
  }

  render () {
    const { children, className } = this.props
    const {
      currentTrigger,
      dropdownStyles,
      ddFirstTime,
      arrowCorrectionX
    } = this.state
    const {
      handleMouseEnter,
      handleMouseLeave,
      startCloseTimeout,
      stopCloseTimeout
    } = this
    return (
      <div className={`dd-wrapper ${className || ''}`}>
        <SmoothDropdownContext.Provider
          value={{
            portal: this.portalRef.current || document.createElement('ul'),
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
            <div className='dd__list' ref={this.portalRef} />
            <div
              className='dd__arrow'
              style={{ left: `calc(50% + ${arrowCorrectionX}px)` }}
            />
            <div className='dd__bg' />
          </div>
        </SmoothDropdownContext.Provider>
      </div>
    )
  }
}

export default SmoothDropdown
