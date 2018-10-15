import React from 'react'

import './HelpPopupIcon.css'

const HelpPopupIcon = ({ onClick, className = '' }) => {
  return (
    <div className={`HelpPopupIcon ${className}`} onClick={onClick}>
      <span className='HelpPopupIcon__symbol'>?</span>
    </div>
  )
}

export default HelpPopupIcon
