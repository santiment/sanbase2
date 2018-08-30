import React from 'react'
import { Icon } from 'semantic-ui-react'

const TrendsExamplesItemIcon = ({ name }) => {
  return (
    <div className='TrendsExamplesItem__icon'>
      <Icon name={name} />
    </div>
  )
}

export default TrendsExamplesItemIcon
