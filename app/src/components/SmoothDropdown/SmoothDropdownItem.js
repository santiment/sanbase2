import React, { Component, Fragment } from 'react'
import ReactDOM from 'react-dom'
import PropTypes from 'prop-types'
import cx from 'classnames'
import { SmoothDropdownContext, ddAsyncUpdateTimeout } from './SmoothDropdown'

const ddItemAsyncUpdateTimeout = ddAsyncUpdateTimeout + 5

class SmoothDropdownItem extends Component {
  dropdownRef = React.createRef()
  triggerRef = React.createRef()

  static propTypes = {
    children: PropTypes.oneOfType([PropTypes.element, PropTypes.string])
      .isRequired,
    trigger: PropTypes.element.isRequired,
    showIf: PropTypes.func,
    id: PropTypes.string
  }

  componentDidMount () {
    this.mountTimer = setTimeout(
      () => this.forceUpdate(),
      ddItemAsyncUpdateTimeout
    ) // VERY HACKY - NECESSARY TO UPDATE DROPDOWN IN DOM
  }
  componentWillUnmount () {
    clearTimeout(this.mountTimer)
    this.dropdownRef = null
    this.triggerRef = null
  }

  render () {
    const { trigger, children, id, className, showIf } = this.props
    const {
      triggerRef: { current: ddTrigger },
      dropdownRef: { current: ddDropdown }
    } = this
    if (!trigger) {
      return null
    }
    return (
      <SmoothDropdownContext.Consumer>
        {({
          portal,
          handleMouseEnter,
          handleMouseLeave,
          currentTrigger,
          startCloseTimeout,
          stopCloseTimeout
        }) => (
          <Fragment>
            <div
              onMouseEnter={evt => {
                if (showIf ? showIf(evt) : true) {
                  handleMouseEnter(ddTrigger, ddDropdown)
                }
              }}
              onMouseLeave={handleMouseLeave}
              className='dd__trigger'
              ref={this.triggerRef}
            >
              {trigger}
            </div>
            {ReactDOM.createPortal(
              <div
                id={id}
                className={cx({
                  dd__item: true,
                  active: ddTrigger === currentTrigger
                })}
                ref={this.dropdownRef}
              >
                <div
                  className={`dd__content ${className || ''}`}
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
      </SmoothDropdownContext.Consumer>
    )
  }
}

export default SmoothDropdownItem
