import React, { Component } from 'react'
import { Input } from 'semantic-ui-react'
import GuideTopic from './GuideTopic'
import GuideDescription from './GuideDescription'
import help from './../../assets/help.json'

import './Guide.scss'

const topics = [...Object.values(help)]

const HiddenElement = () => ''

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
            <h2>Choose a topic to describe</h2>
          )}
        </div>
        <div className='Guide__right'>
          <HiddenElement>
            {
              // TODO: add ability to choose topics from keyboard
            }
            <Input
              className='Guide__search'
              icon='search'
              iconPosition='left'
              onChange={this.handleSearchTermChange}
            />
          </HiddenElement>
          <ol className='Guide__topics'>
            {topics
              .filter(({ title }) =>
                title.toUpperCase().includes(searchTerm.toUpperCase())
              )
              .map(topic => (
                <GuideTopic
                  key={topic.title}
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
