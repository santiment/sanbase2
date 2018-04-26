import React, { Component } from 'react'
import PropTypes from 'prop-types'
import CreatableSelect from 'react-select/lib/Creatable'

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
        <CreatableSelect
          isMulti
          placeholder='Add a tag...'
          options={[
            {value: 'Santiment', label: 'SAN'},
            {value: 'EOS', label: 'EOS'}
          ]}
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
