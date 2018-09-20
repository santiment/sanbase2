import React, { Component } from 'react'
import { connect } from 'react-redux'
import TrendsExamplesItem from './TrendsExamplesItem'
import { gotoExplore } from '../trendsUtils'
import './TrendsExamples.css'

const examples = [
  {
    topic: 'stablecoin',
    settings: {
      interval: '3m',
      sources: ['merged']
    }
  },
  {
    topic: 'etf',
    settings: {
      interval: '3m',
      sources: ['telegram', 'reddit']
    }
  },
  {
    topic: 'ico',
    settings: {
      interval: '3m',
      sources: ['professional_traders_chat']
    }
  }
]

export class TrendsExamples extends Component {
  handleExampleClick = ({ currentTarget }) => {
    this.props.gotoExplore(
      currentTarget.dataset.topic + '?' + currentTarget.dataset.settings
    )
  }
  render () {
    return (
      <ul className='TrendsExamples'>
        {examples.map(({ topic, settings }) => (
          <TrendsExamplesItem
            key={topic}
            topic={topic}
            settings={settings}
            onClick={this.handleExampleClick}
          />
        ))}
      </ul>
    )
  }
}

export default connect(null, gotoExplore)(TrendsExamples)
