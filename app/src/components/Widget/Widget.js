import React from 'react'

import './Widget.css'

const Widget = ({ children, title, className = '' }) => {
  return (
    <div className={'Widget ' + className}>
      {title && <h2 className='Widget__title'>{title}</h2>}
      <div className='Widget__content'>{children}</div>
    </div>
  )
}

export default Widget
