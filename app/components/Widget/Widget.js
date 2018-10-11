import React from 'react'

import './Widget.css'

const Widget = ({ children, className }) => {
  return <div className={'Widget ' + className || ''}>{children}</div>
}

export default Widget
