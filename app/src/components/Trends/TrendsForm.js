import React, { Component } from 'react'
import { Query } from 'react-apollo'
import { trendsExploreGQL } from './trendsExploreGQL'

export class TrendsForm extends Component {
  state = {
    topic: ''
  }

  handleChange = evt => {
    this.setState({ topic: evt.target.value })
  }

  render () {
    const { topic } = this.state
    return (
      <div>
        <Query
          query={trendsExploreGQL}
          variables={{ searchText: topic }}
          onCompleted={() =>
            this.props.history.push(`/trends/explore/${topic}`)
          }
        >
          {trendsExplore => (
            <form onSubmit={trendsExplore}>
              <input
                type='text'
                value={this.state.topic}
                onChange={this.handleChange}
              />
              <button type='submit'>Submit</button>
            </form>
          )}
        </Query>
      </div>
    )
  }
}

export default TrendsForm
