import React from 'react'
import cx from 'classnames'
import './TrendsExploreTimeFilterOption.css'

const TrendsExploreTimeFilterOption = ({ label, isActive, onClick }) => {
  return (
    <li
      className={cx({
        TrendsExploreTimeFilterOption: true,
        TrendsExploreTimeFilterOption_active: isActive
      })}
    >
      <label htmlFor={`trend-time-${label}`} onClick={onClick}>
        {label}
      </label>
      <input
        type='radio'
        name='trend-time'
        value={label}
        id={`trend-time-${label}`}
      />
    </li>
  )
}

export default TrendsExploreTimeFilterOption
