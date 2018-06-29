import React from 'react'

import './HelpPopupIcon.css'

const HelpPopupIcon = ({ onClick }) => {
  return (
    <div className='HelpPopupIcon' onClick={onClick}>
      <span className='HelpPopupIcon__symbol'>?</span>
    </div>
  )
}

export default HelpPopupIcon
