import React from 'react'
import './Panel.css'

const Panel = ({children, withoutHeader}) => {
  let cls = 'panel'
  if (withoutHeader) {
    cls += ' panel-without-header'
  }
  return (
    <div className={cls}>
      {children}
    </div>
  )
}

export default Panel
