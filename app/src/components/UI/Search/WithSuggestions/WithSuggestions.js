import React, { PureComponent } from 'react'
import PropTypes from 'prop-types'
import Search from '../Search'
import styles from './WithSuggestions.scss'

class SearchWithSuggestions extends PureComponent {
  static propTypes = {
    data: PropTypes.array.isRequired,
    suggestionContent: PropTypes.func.isRequired,
    predicate: PropTypes.func.isRequired,
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
    const { data, predicate } = this.props
    this.setState(prevState => ({
      ...prevState,
      suggestions: data.filter(predicate(prevState.searchTerm))
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
    const { maxSuggestions, suggestionContent } = this.props
    return (
      <div className={styles.wrapper}>
        <Search
          value={searchTerm}
          onFocus={this.toggleFocusState}
          onBlur={this.toggleFocusState}
          onChange={this.handleInputChange}
        />
        {isFocused &&
          searchTerm !== '' && (
          <ul className={styles.suggestions}>
            {suggestions.length !== 0 ? (
              suggestions.slice(0, maxSuggestions).map(suggestion => (
                <li className={styles.suggestions__item}>
                  <div className={styles.suggestion}>
                    {suggestionContent(suggestion)}
                  </div>
                </li>
              ))
            ) : (
              <div className={styles.suggestion + ' ' + styles.noresults}>
                  No results found.
              </div>
            )}
          </ul>
        )}
      </div>
    )
  }
}

export default SearchWithSuggestions
