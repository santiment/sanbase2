import React from 'react'
import cx from 'classnames'
import './PercentChanges.css'

export const PercentChanges = ({changes}) => {
  if (!changes) { return '' }
  const normalizedChanges = parseFloat(changes).toFixed(2)
  return (
    <div className={cx({
      'percent-changes': true,
      'percent-changes--positive': normalizedChanges >= 0,
      'percent-changes--negative': normalizedChanges < 0
    })}>
      <i className={cx({
        'fa': true,
        'fa-caret-up': changes >= 0,
        'fa-caret-down': changes < 0
      })} />&nbsp;
      {normalizedChanges < 0
        ? normalizedChanges.toString().split('-')[1]
        : normalizedChanges}%
    </div>
  )
}

export default PercentChanges
