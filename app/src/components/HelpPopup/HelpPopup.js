import React from 'react'
import { Popup } from 'semantic-ui-react'
import HelpPopupIcon from './HelpPopupIcon'

const style = {
  maxWidth: 417,
  padding: '2rem 1.8rem'
}

const HelpPopup = ({ children, content, trigger = <HelpPopupIcon /> }) => {
  const render = content || children
  return (
    <Popup
      content={render}
      trigger={trigger}
      position='bottom left'
      on='click'
      style={style}
    />
  )
}

export default HelpPopup
