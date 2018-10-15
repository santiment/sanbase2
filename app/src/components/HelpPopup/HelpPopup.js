import React from 'react'
import { Popup } from 'semantic-ui-react'
import HelpPopupIcon from './HelpPopupIcon'

export const style = {
  maxWidth: 465,
  padding: '2rem 1.8rem'
}

const HelpPopup = ({
  children,
  content,
  className,
  trigger = <HelpPopupIcon className={className} />
}) => {
  const render = content || children
  return (
    <Popup
      content={render}
      trigger={trigger}
      position='bottom center'
      on='hover'
      style={style}
    />
  )
}

export default HelpPopup
