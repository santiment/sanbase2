import React, { Component } from 'react'
import PropTypes from 'prop-types'
import debounce from 'lodash.debounce'
import { Search, Input, Ref } from 'semantic-ui-react'
import './Search.css'

const resultRenderer = ({ name, ticker }) => {
  return (
    <div id='search-result'>
      {name} ({ticker})
    </div>
  )
}

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

class SearchPanel extends Component {
  constructor (props) {
    super(props)

    this.state = {
      isLoading: false,
      results: [],
      value: undefined
    }
    this.handleResultSelect = this.handleResultSelect.bind(this)
    this.handleSearchChange = this.handleSearchChange.bind(this)
    this.handleDebouncedChange = this.handleDebouncedChange.bind(this)
    this.handleDebouncedChange = debounce(this.handleDebouncedChange, 100)
  }

  handleSearchRef = c => {
    this._searchInput = c && c.querySelector('input')
  }

  componentWillReceiveProps (nextProps) {
    if (nextProps.focus && this._searchInput) {
      this._searchInput.focus()
      this.props.resetFocus()
    }
  }

  handleDebouncedChange (value) {
    const results = this.props.projects
      .filter(el => {
        const name = el.name || ''
        const ticker = el.ticker || ''
        return (
          name.toLowerCase().indexOf(value.toLowerCase()) !== -1 ||
          ticker.toLowerCase().indexOf(value.toLowerCase()) !== -1
        )
      })
      .map((el, index) => {
        return {
          name: el.name,
          ticker: el.ticker,
          cmcid: el.coinmarketcapId,
          key: index
        }
      })

    this.setState({
      isLoading: false,
      results: results
    })
  }

  handleResultSelect (e, { result }) {
    this.setState({ value: '' }, () => {
      this._searchInput.blur()
      this._searchInput.value = ''
      this.props.onSelectProject(result.cmcid)
    })
  }

  handleSearchChange (e, { value }) {
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
      this.handleDebouncedChange(searchText)
    )
  }

  render () {
    return (
      <div className='search-panel'>
        <Ref innerRef={this.handleSearchRef}>
          <Search
            className={this.props.loading ? '' : 'search-data-loaded'}
            key={'search'}
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
  onSelectProject: PropTypes.func
}

SearchPanel.defaultProps = {
  projects: []
}

export default SearchPanel
