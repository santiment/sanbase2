import React, { Component } from 'react'

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
      <div>
        <form onSubmit={this.handleSubmit}>
          <input
            type='text'
            value={this.state.topic}
            onChange={this.handleChange}
          />
          <button type='submit'>Submit</button>
        </form>
      </div>
    )
  }
}

export default TrendsForm
