import React, { Component, Fragment } from 'react'

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
    (this.dropdownTimer = setTimeout(() => this.closeDropdown(), 50))

  stopCloseTimeout = () => clearTimeout(this.dropdownTimer)

  openDropdown = trigger => {
    if (!trigger) return
    if (dropdowns.has(trigger)) {
      this.setState(prevState => ({
        ...prevState,
        currentTrigger: trigger
      }))
    }
    // const { currentTrigger } = this.state

    const dropdown = dropdowns.get(trigger)
    const triggerMeta = trigger.getBoundingClientRect()
    const ddMeta = dropdown.getBoundingClientRect()

    // ddList.style.opacity = 1
    // ddList.style.left =
    //   triggerMeta.left - (ddMeta.width / 2 - triggerMeta.width / 2) + 'px'
    const left =
      triggerMeta.left - (ddMeta.width / 2 - triggerMeta.width / 2) + 'px'
    const width = ddMeta.width + 'px'
    const height = ddMeta.height + 'px'

    this.setState(prevState => ({
      ...prevState,
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
    console.log(trigger)
    this.stopCloseTimeout()
    this.openDropdown(trigger)
  }

  handleMouseLeave = () => this.startCloseTimeout()

  render () {
    const { children } = this.props
    const { currentTrigger, dropdownStyles } = this.state
    const { handleMouseEnter, handleMouseLeave } = this
    return (
      <Fragment>
        {children('tester')}
        <div className='dd dropdown-holder'>
          <div class='dd__arrow dropdown__arrow' />
          <div
            class='dd__bg dropdown__bg'
            style={currentTrigger && dropdownStyles}
          />
          <SmoothDdContext.Provider
            value={{
              portal: this.portalRef.current,
              currentTrigger,
              handleMouseEnter,
              handleMouseLeave
            }}
          >
            <div
              className='dd__list dropdown__wrap'
              style={currentTrigger && dropdownStyles}
              ref={this.portalRef}
            />
          </SmoothDdContext.Provider>
        </div>
      </Fragment>
    )
  }
}

export default SmoothDD
