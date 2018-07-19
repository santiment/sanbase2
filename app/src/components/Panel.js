import React from 'react'
import cx from 'classnames'
import './Panel.css'

const Panel = ({ children, withoutHeader, zero, className }) => (
  <div
    className={cx({
      panel: true,
      'panel-without-header': withoutHeader,
      'panel-zero': zero,
      [className]: className
    })}
  >
    {children}
  </div>
)

export default Panel
