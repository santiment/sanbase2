import React, { Component } from 'react'
import { Icon, Input } from 'semantic-ui-react'

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

  render () {
    const { searchTerm } = this.state

    return (
      <div className='Guide'>
        <div className='Guide__left'>
          <div className='Guide__description'>asdf sadf asdfas dfasfdsdf</div>
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
                <li className='Guide__topic'>{topic.title}</li>
              ))}
          </ol>
        </div>
      </div>
    )
  }
}

export default Guide
