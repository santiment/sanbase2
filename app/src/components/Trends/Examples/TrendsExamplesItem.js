import React from 'react'
import PropTypes from 'prop-types'
import TrendsExamplesItemChart from './TrendsExamplesItemChart'
import './TrendsExamplesItem.css'

const propTypes = {
  topic: PropTypes.string.isRequired,
  onClick: PropTypes.func.isRequired
}

const TrendsExamplesItem = ({ topic, onClick }) => {
  return (
    <li className='TrendsExamplesItem' onClick={onClick} data-topic={topic}>
      <div className='TrendsExamplesItem__topic'>
        <span>{topic}</span>
      </div>
      <div className='TrendsExamplesItem__chart'>
        <TrendsExamplesItemChart topic={topic} />
      </div>
      <div className='TrendsExamplesItem__settings'>
        For 7 days, Merged sources
      </div>
    </li>
  )
}

TrendsExamplesItem.propTypes = propTypes

export default TrendsExamplesItem
