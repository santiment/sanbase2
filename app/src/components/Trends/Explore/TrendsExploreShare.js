import React from 'react'
import { Button } from 'semantic-ui-react'
import SmoothDropdown from '../../SmoothDropdown/SmoothDropdown'
import SmoothDropdownItem from '../../SmoothDropdown/SmoothDropdownItem'
import ShareOptions from '../../ShareOptions/ShareOptions'
import './TrendsExploreShare.css'

const TrendsExploreShare = ({ topic }) => {
  const title = `Crypto Social Trends for "${topic}"`

  return (
    <SmoothDropdown>
      <SmoothDropdownItem
        trigger={
          <Button
            id='TrendsExploreShare'
            basic
            className='link'
            icon='share alternate'
          />
        }
      >
        <ShareOptions title={title} url={window.location.href} />
      </SmoothDropdownItem>
    </SmoothDropdown>
  )
}

export default TrendsExploreShare
