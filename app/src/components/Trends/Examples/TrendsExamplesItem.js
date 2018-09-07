import React from 'react'
import PropTypes from 'prop-types'
import queryString from 'query-string'
import TrendsExamplesItemChart from './TrendsExamplesItemChart'
import { parseExampleSettings } from '../trendsUtils'
import './TrendsExamplesItem.css'

const propTypes = {
  topic: PropTypes.string.isRequired,
  settings: PropTypes.object,
  onClick: PropTypes.func.isRequired
}

const TrendsExamplesItem = ({ topic, settings, onClick }) => {
  return (
    <li
      className='TrendsExamplesItem'
      onClick={onClick}
      data-topic={topic}
      data-settings={queryString.stringify(
        {
          interval: settings.interval,
          source: settings.sources
        },
        { arrayFormat: 'bracket' }
      )}
    >
      <div className='TrendsExamplesItem__topic'>
        <span>{topic}</span>
      </div>
      <div className='TrendsExamplesItem__chart'>
        <TrendsExamplesItemChart
          topic={topic}
          selectedSources={settings.sources}
        />
      </div>
      <div className='TrendsExamplesItem__settings'>
        {parseExampleSettings(settings)}
      </div>
    </li>
  )
}

TrendsExamplesItem.propTypes = propTypes

export default TrendsExamplesItem
