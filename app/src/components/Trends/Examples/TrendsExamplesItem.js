import React, { Fragment } from 'react'
import PropTypes from 'prop-types'
import { Icon } from 'semantic-ui-react'
import TrendsExamplesItemChart from './TrendsExamplesItemChart'
import TrendsExamplesItemQuery from './TrendsExamplesItemQuery'
import TrendsExamplesItemIcon from './TrendsExamplesItemIcon'
import './TrendsExamplesItem.css'

const propTypes = {
  query: PropTypes.string,
  settings: PropTypes.string,
  onClick: PropTypes.func
}

const TrendsExamplesItem = ({ query, settings, onClick }) => {
  return (
    <li className='TrendsExamplesItem' onClick={onClick} data-query={query}>
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

TrendsExamplesItem.propTypes = propTypes

export default TrendsExamplesItem
