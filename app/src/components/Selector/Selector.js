import React, { Component } from 'react'
import PropTypes from 'prop-types'
import cx from 'classnames'
import './Selector.css'

export const SelectorItem = ({
  isSelected = false,
  value = 'all',
  setFilter,
  disabled = false
}) => (
  <div
    className={cx({
      'selector-item': true,
      'selector-item--selected': isSelected,
      'selector-item--disabled': disabled
    })}
    onClick={() => !disabled && setFilter(value)}
  >
    {value}
  </div>
)

class Selector extends Component {
  state = {
    selected: this.props.defaultSelected
  }

  static defaultProps = {
    defaultSelected: undefined,
    options: [],
    disabled: false
  }

  static propTypes = {
    defaultSelected: PropTypes.string,
    options: PropTypes.array,
    onSelectOption: PropTypes.func,
    disabled: PropTypes.bool
  }

  onSelectOption = newOption => {
    this.setState({ selected: newOption }, () => {
      this.props.onSelectOption(newOption)
    })
  }

  render () {
    const { selected } = this.state
    const { options, disabled } = this.props
    return (
      <div className='selector'>
        {options.map(option => (
          <SelectorItem
            key={option}
            isSelected={selected === option}
            value={option}
            setFilter={this.onSelectOption}
            disabled={disabled}
          />
        ))}
      </div>
    )
  }
}

export default Selector
