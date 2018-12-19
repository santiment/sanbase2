import React from 'react'

import './HelpPopupIcon.css'

const HelpPopupIcon = ({ onClick, className = '', ...props }) => {
  return (
    <div className={`HelpPopupIcon ${className}`} onClick={onClick} {...props}>
      <span className='HelpPopupIcon__symbol'>?</span>
    </div>
  )
}

export default HelpPopupIcon
