import React, { Component } from 'react'
import { Icon, Input } from 'semantic-ui-react'
import GuideTopic from './GuideTopic'
import GuideDescription from './GuideDescription'

import './Guide.scss'

const topics = [
  {
    title: 'Token aging'
  },
  {
    title: 'Transaction volume'
  },
  {
    title: 'Development activity'
  }
]

class Guide extends Component {
  state = {
    searchTerm: ''
  }

  handleSearchTermChange = ({ currentTarget }) => {
    this.setState({
      searchTerm: currentTarget.value
    })
  }

  handleTopicClick = topic => {
    this.setState({
      currentTopic: topic
    })
  }

  render () {
    const { searchTerm, currentTopic } = this.state

    return (
      <div className='Guide'>
        <div className='Guide__left'>
          {currentTopic ? (
            <GuideDescription topic={currentTopic} />
          ) : (
            'Choose a topic'
          )}
        </div>
        <div className='Guide__right'>
          <Input
            className='Guide__search'
            icon='search'
            iconPosition='left'
            onChange={this.handleSearchTermChange}
          />
          <ol className='Guide__topics'>
            {topics
              .filter(({ title }) =>
                title.toUpperCase().includes(searchTerm.toUpperCase())
              )
              .map(topic => (
                <GuideTopic
                  topic={topic}
                  isActive={currentTopic === topic}
                  onClick={this.handleTopicClick}
                />
              ))}
          </ol>
        </div>
      </div>
    )
  }
}

export default Guide
