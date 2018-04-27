import React, { Component } from 'react'
import PropTypes from 'prop-types'
import Select from 'react-select'
import tags from './../Insights/tags.json'

const getOptionsFromTags = tags => {
  return tags.allTags.map((tag, index) => {
    return {value: tag.name, label: tag.name}
  })
}

class TagsField extends Component {
  state = { // eslint-disable-line
    tags: []
  }

  handleOnChange = tags => { // eslint-disable-line
    if (tags.length <= 5) {
      this.setState({tags}, () => {
        this.props.setTags(tags)
      })
    }
  }

  render () {
    return (
      <div>
        <label>Tags</label>
        <Select
          isMulti
          placeholder='Add a tag...'
          options={getOptionsFromTags(tags)}
          onChange={this.handleOnChange}
          value={this.state.tags}
        />
        <div className='hint'>
          Up to 5 tags
        </div>
      </div>
    )
  }
}

TagsField.propTypes = {
  setTags: PropTypes.func.isRequired
}

export default TagsField
