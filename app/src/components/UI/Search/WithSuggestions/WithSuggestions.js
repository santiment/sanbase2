import React, { PureComponent } from 'react'
import PropTypes from 'prop-types'
import Search from '../Search'

/*
    background-color: #23252a;
    border-color: #4a4a4a;
*/

class SearchWithSuggestions extends PureComponent {
  static propTypes = {
    data: PropTypes.array.isRequired,
    maxSuggestions: PropTypes.number
  }

  static defaultProps = {
    maxSuggestions: 5
  }

  state = {
    suggestions: [],
    searchTerm: '',
    isFocused: false
  }

  handleInputChange = ({ currentTarget }) => {
    this.setState(
      prevState => ({
        ...prevState,
        searchTerm: currentTarget.value
      }),
      this.filterData
    )
  }

  filterData () {
    this.setState(prevState => ({
      ...prevState,
      suggestions: this.props.data.filter(item => {
        return item.toUpperCase().includes(prevState.searchTerm.toUpperCase())
      })
    }))
  }

  toggleFocusState = () => {
    this.setState(prevState => ({
      ...prevState,
      isFocused: !prevState.isFocused
    }))
  }

  render () {
    const { suggestions, searchTerm, isFocused } = this.state
    const { maxSuggestions } = this.props
    return (
      <div>
        <Search
          onFocus={this.toggleFocusState}
          onBlur={this.toggleFocusState}
          value={searchTerm}
          onChange={this.handleInputChange}
        />
        {isFocused &&
          searchTerm !== '' && (
          <div className='suggestions'>
            {suggestions.length !== 0
              ? suggestions
                .slice(0, maxSuggestions)
                .map(suggestion => <div className='sug'>{suggestion}</div>)
              : 'No results found.'}
          </div>
        )}
      </div>
    )
  }
}

export default SearchWithSuggestions
