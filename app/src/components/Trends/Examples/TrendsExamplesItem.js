import React, { Fragment } from 'react'
import { Icon } from 'semantic-ui-react'
import TrendsExamplesItemChart from './TrendsExamplesItemChart'
import TrendsExamplesItemQuery from './TrendsExamplesItemQuery'
import TrendsExamplesItemIcon from './TrendsExamplesItemIcon'
import './TrendsExamplesItem.css'

const TrendsExamplesItem = ({ query, settings }) => {
  return (
    <li className='TrendsExamplesItem'>
      <TrendsExamplesItemQuery query={query} />
      <div className='TrendsExamplesItem__chart'>
        <TrendsExamplesItemChart query={query} settings={settings} />
      </div>
      <div className='TrendsExamplesItem__settings'>
        {/* <TrendsExamplesItemIcon name='settings' /> */}
        For 7 days, Merged sources
      </div>
    </li>
  )
}

export default TrendsExamplesItem
