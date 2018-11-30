import React, { Component } from 'react'
import PropTypes from 'prop-types'
import cx from 'classnames'
import './Selector.css'

export const SelectorItem = ({
  isSelected = false,
  value = 'all',
  name = 'all',
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
    {name}
  </div>
)

export class Selector extends Component {
  state = {
    selected: this.props.defaultSelected
  }

  static defaultProps = {
    defaultSelected: undefined,
    options: [],
    disabled: false,
    className: ''
  }

  static propTypes = {
    defaultSelected: PropTypes.string,
    options: PropTypes.array,
    onSelectOption: PropTypes.func,
    disabled: PropTypes.bool,
    className: PropTypes.string
  }

  static getDerivedStateFromProps (nextProps, prevState) {
    if (nextProps.defaultSelected !== prevState.selected) {
      return {
        selected: nextProps.defaultSelected
      }
    }
    return prevState
  }

  onSelectOption = newOption => {
    this.setState({ selected: newOption }, () => {
      this.props.onSelectOption(newOption)
    })
  }

  render () {
    const { selected } = this.state
    const { options, disabled, className } = this.props
    const nameOptions = this.props.nameOptions || options
    return (
      <div className={`selector ${className}`}>
        {options.map((option, index) => (
          <SelectorItem
            key={option}
            name={nameOptions[index]}
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
