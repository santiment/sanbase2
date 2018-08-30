import React, { Component } from 'react'
import { Input } from 'semantic-ui-react'
import './TrendsForm.css'

export class TrendsForm extends Component {
  state = {
    topic: ''
  }

  handleSubmit = evt => {
    evt.preventDefault()
    this.props.history.push(`/trends/explore/${this.state.topic}`)
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
            icon='search'
            iconPosition='right'
            placeholder='Enter your search query'
            value={this.state.topic}
            onChange={this.handleChange}
          />
        </form>
      </div>
    )
  }
}

export default TrendsForm
