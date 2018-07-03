import React, { Component } from 'react'
import gql from 'graphql-tag'
import { graphql } from 'react-apollo'
import PropTypes from 'prop-types'
import Select from 'react-select'

const allTagsGQL = gql`{
  allTags {
    name
  }
}
`

const getOptionsFromTags = tags => {
  return (tags.allTags || []).map((tag, index) => {
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
          options={this.props.tags}
          isLoading={this.props.isTagsLoading}
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

const mapDataToProps = ({allTags}) => ({
  tags: getOptionsFromTags(allTags),
  isTagsLoading: allTags.isLoading
})

const enhance =
graphql(allTagsGQL, {
  name: 'allTags',
  props: mapDataToProps,
  options: () => {
    return {
      errorPolicy: 'all'
    }
  }
})

export default enhance(TagsField)
