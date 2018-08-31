import React, { Component } from 'react'
import PropTypes from 'prop-types'
import TrendsExamplesItem from './TrendsExamplesItem'
import './TrendsExamples.css'

const examples = [
  { query: 'crypto', description: 'some description', settings: '' },
  { query: 'btc', description: 'some description', settings: '' },
  { query: 'eth', description: 'some description', settings: '' }
]

export class TrendsExamples extends Component {
  handleExampleClick = ({ currentTarget }) => {
    this.props.history.push(`/trends/explore/${currentTarget.dataset.query}`)
  }
  render () {
    return (
      <ul className='TrendsExamples'>
        {examples.map(({ query, description, settings }, index) => (
          <TrendsExamplesItem
            key={index}
            query={query}
            description={description}
            settings={settings}
            onClick={this.handleExampleClick}
          />
        ))}
      </ul>
    )
  }
}

TrendsExamples.propTypes = {
  history: PropTypes.object
}

export default TrendsExamples

/* TODO:
  1. Settings interface
*/
