import React from 'react'
import './Panel.css'

const Panel = ({children, withoutHeader, zero}) => {
  let cls = 'panel'
  if (withoutHeader) {
    cls += ' panel-without-header'
  }
  if (zero) {
    cls += ' panel-zero'
  }
  return (
    <div className={cls}>
      {children}
    </div>
  )
}

export default Panel
