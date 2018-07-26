import React, { Component } from 'react'
import PropTypes from 'prop-types'
import debounce from 'lodash.debounce'
import { Search, Input, Ref } from 'semantic-ui-react'
import './Search.css'

const resultRenderer = ({ name, ticker }) => (
  <div id='search-result'>
    {name} ({ticker})
  </div>
)

const CustomInput = (
  <div>
    <Input
      id='search-input'
      icon='search'
      iconPosition='left'
      placeholder='Search...'
    />
    <span>/</span>
  </div>
)

const contains = (str1, str2) => str1.search(new RegExp(str2, 'i')) === 0

class SearchPanel extends Component {
  state = {
    isLoading: false,
    results: [],
    value: undefined
  }

  handleSearchRef = c => {
    this._searchInput = c && c.querySelector('input')
  }

  componentWillReceiveProps (nextProps) {
    if (!this.state.isLoading && nextProps.focus && this._searchInput) {
      this._searchInput.focus()
      this.props.resetFocus()
    }
  }

  searchResults = debounce(searchText => {
    const results = this.props.projects
      .filter(
        ({ name = '', ticker = '' }) =>
          contains(name, searchText) || contains(ticker, searchText)
      )
      .map((el, index) => ({
        ticker: el.ticker,
        name: el.name,
        cmcid: el.coinmarketcapId,
        key: index
      }))

    this.setState({
      results,
      isLoading: false
    })
  }, 100)

  handleResultSelect = (e, { result }) => {
    this.setState({ value: '' }, () => {
      this._searchInput.blur()
      this._searchInput.value = ''
      this.props.onSelectProject(result.cmcid)
    })
  }

  handleSearchChange = (e, { value }) => {
    const searchText = (value => {
      if (value === '/') {
        return ''
      }
      if (value.endsWith('/')) {
        return value.substring(0, value.length - 1)
      }
      return value
    })(value)
    this._searchInput.value = searchText
    this.setState({ isLoading: true, value: searchText }, () =>
      this.searchResults(searchText)
    )
  }

  render () {
    return (
      <div className='search-panel'>
        <Ref innerRef={this.handleSearchRef}>
          <Search
            className={this.props.loading ? '' : 'search-data-loaded'}
            loading={this.state.isLoading || this.props.loading}
            onResultSelect={this.handleResultSelect}
            onSearchChange={this.handleSearchChange}
            results={this.state.results}
            value={this.state.value}
            resultRenderer={resultRenderer}
            selectFirstResult
            input={CustomInput}
          />
        </Ref>
      </div>
    )
  }
}

SearchPanel.propTypes = {
  projects: PropTypes.array,
  onSelectProject: PropTypes.func,
  resetFocus: PropTypes.func
}

SearchPanel.defaultProps = {
  onSelectProject: () => {},
  resetFocus: () => {},
  projects: []
}

export default SearchPanel
