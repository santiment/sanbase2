import React, { Component } from 'react'
import PropTypes from 'prop-types'
import cx from 'classnames'
import './TimeFilter.css'

const timeOptionsDefault = ['1w', '1m', '3m', '6m', '1y', 'all']

export const TimeFilterItem = ({
  isSelected = false,
  value = 'all',
  setFilter,
  disabled = false
}) => (
  <div
    className={cx({
      'time-filter-item': true,
      'time-filter-item--selected': isSelected,
      'time-filter-item--disabled': disabled
    })}
    onClick={() => !disabled && setFilter(value)}
  >
    {value}
  </div>
)

class TimeFilter extends Component {
  state = {
    selected: this.props.defaultSelected
  }

  static defaultProps = {
    defaultSelected: 'all',
    timeOptions: timeOptionsDefault,
    disabled: false
  }

  static propTypes = {
    defaultSelected: PropTypes.string,
    timeOptions: PropTypes.array,
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
    const { timeOptions, disabled } = this.props
    return (
      <div className='time-filter'>
        {timeOptions.map(option => (
          <TimeFilterItem
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

export default TimeFilter
