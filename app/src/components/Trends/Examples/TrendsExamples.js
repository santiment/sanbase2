import React, { Component } from 'react'
import { connect } from 'react-redux'
import TrendsExamplesItem from './TrendsExamplesItem'
import { gotoExplore } from '../trendsUtils'
import './TrendsExamples.css'

const examples = [{ topic: 'crypto' }, { topic: 'btc' }, { topic: 'eth' }]

export class TrendsExamples extends Component {
  handleExampleClick = ({ currentTarget }) => {
    this.props.gotoExplore(currentTarget.dataset.topic)
  }
  render () {
    return (
      <ul className='TrendsExamples'>
        {examples.map(({ topic }) => (
          <TrendsExamplesItem
            key={topic}
            topic={topic}
            onClick={this.handleExampleClick}
          />
        ))}
      </ul>
    )
  }
}

export default connect(null, gotoExplore)(TrendsExamples)
