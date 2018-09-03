import React from 'react'
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

export const TimeFilter = ({
  selected = 'all',
  timeOptions = timeOptionsDefault,
  setFilter,
  disabled = false
}) => (
  <div className='time-filter'>
    {timeOptions.map(option => (
      <TimeFilterItem
        key={option}
        isSelected={selected === option}
        value={option}
        setFilter={setFilter}
        disabled={disabled}
      />
    ))}
  </div>
)

export default TimeFilter
