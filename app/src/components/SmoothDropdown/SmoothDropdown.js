import React, { Component } from 'react'
import cx from 'classnames'
import './SmoothDropdown.css'

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

  handleMouseEnter = (trigger, dropdown) => {
    this.stopCloseTimeout()
    this.openDropdown(trigger, dropdown)
  }

  handleMouseLeave = () => this.startCloseTimeout()

  openDropdown = (trigger, dropdown) => {
    const ddContent = dropdown.querySelector('.dd__content')

    const left =
      trigger.offsetLeft -
      (ddContent.clientWidth - trigger.clientWidth) / 2 +
      'px'
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
      }
    }))
  }

  closeDropdown = () => {
    this.setState(prevState => ({
      ...prevState,
      currentTrigger: null
    }))
  }

  render () {
    const { children, className } = this.props
    const { currentTrigger, dropdownStyles, ddFirstTime } = this.state
    const {
      portalRef,
      handleMouseEnter,
      handleMouseLeave,
      startCloseTimeout,
      stopCloseTimeout
    } = this
    return (
      <div className={`${className} dd-wrapper`}>
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
            <div className='dd__list' ref={portalRef} />
            <div className='dd__arrow' />
            <div className='dd__bg' />
          </div>
        </SmoothDropdownContext.Provider>
      </div>
    )
  }
}

export default SmoothDropdown
