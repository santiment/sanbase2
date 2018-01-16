import React from 'react'
import cx from 'classnames'
import './PercentChanges.css'

export const PercentChanges = ({changes}) => (
  <div className={cx({
    'percent-changes': true,
    'percent-changes--positive': changes >= 0,
    'percent-changes--negative': changes < 0
  })}>
    <i className={cx({
      'fa': true,
      'fa-caret-up': changes >= 0,
      'fa-caret-down': changes < 0
    })} />&nbsp;
    {changes < 0 ? changes.toString().split('-')[1] : changes}%
  </div>
)

export default PercentChanges
