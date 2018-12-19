import React, { Component } from 'react'
import Raven from 'raven-js'
import axios from 'axios'
import GoogleAnalytics from 'react-ga'
import { connect } from 'react-redux'
import { Input } from 'semantic-ui-react'
import { gotoExplore } from './trendsUtils'
import './TrendsForm.css'

export class TrendsForm extends Component {
  state = {
    topic: this.props.defaultTopic || ''
  }

  handleSubmit = evt => {
    evt.preventDefault()
    trackTopicSearch(this.state.topic)
    this.props.gotoExplore(this.state.topic)
  }

  handleChange = evt => {
    this.setState({ topic: evt.target.value })
  }

  render () {
    return (
      <div className='TrendsForm'>
        <form className='TrendsForm__form' onSubmit={this.handleSubmit}>
          <Input
            className='TrendsForm__input'
            icon={this.state.topic.length === 0 && 'search'}
            iconPosition='left'
            placeholder='Enter your search query'
            value={this.state.topic}
            onChange={this.handleChange}
          />
        </form>
      </div>
    )
  }
}

const trackTopicSearch = topic => {
  if (process.env.NODE_ENV === 'production') {
    try {
      axios({
        method: 'post',
        url:
          'https://us-central1-sanbase-search-ea4dc.cloudfunctions.net/trackTrends',
        headers: {
          authorization: ''
        },
        data: { topic }
      })
    } catch (error) {
      Raven.captureException(
        'tracking search trends queries ' + JSON.stringify(error)
      )
    }
    GoogleAnalytics.event({
      category: 'Trends Search',
      action: 'Search: ' + topic
    })
  }
}

export default connect(
  null,
  gotoExplore
)(TrendsForm)
