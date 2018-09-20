import React, { Component } from 'react'
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
            placeholder='Enter your search query'
            value={this.state.topic}
            onChange={this.handleChange}
          />
        </form>
      </div>
    )
  }
}

export default connect(null, gotoExplore)(TrendsForm)
