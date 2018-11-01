import React, { Component, Fragment } from 'react'
import PropTypes from 'prop-types'
import debounce from 'lodash.debounce'
import { Search, Input, Ref } from 'semantic-ui-react'
import ProjectIcon from './../../components/ProjectIcon'
import './Search.css'

const resultRenderer = ({ name, ticker }) => (
  <Fragment>
    <ProjectIcon name={name} ticker={ticker} />
    <div>
      {name} ({ticker})
    </div>
  </Fragment>
)

const CustomInput = (
  <Input
    id='search-input'
    icon='search'
    iconPosition='left'
    placeholder='Search...'
  />
)

const contains = (str1, str2) => str1.search(new RegExp(str2, 'i')) === 0

class SearchPanel extends Component {
  state = {
    isLoading: false,
    results: [],
    value: undefined
  }

  handleSearchRef = c => {
    this._searchInput = c && c.querySelector('#search-input')
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
      .filter((_, index) => index < 10)
      .map((el, index) => ({
        ticker: el.ticker,
        name: el.name,
        title: el.name,
        cmcid: el.coinmarketcapId,
        key: index
      }))

    this.setState({
      results: searchText.length > 0 ? results : [],
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
            className={
              this.props.loading
                ? ''
                : `search-data-loaded ${this.props.className || ''}`
            }
            loading={this.state.isLoading || this.props.loading}
            onResultSelect={this.handleResultSelect}
            onSearchChange={this.handleSearchChange}
            results={this.state.results}
            value={
              this.state.value === undefined
                ? this.props.value
                : this.state.value
            }
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
  projects: PropTypes.array.isRequired,
  focus: PropTypes.bool.isRequired,
  onSelectProject: PropTypes.func,
  resetFocus: PropTypes.func
}

SearchPanel.defaultProps = {
  onSelectProject: () => {},
  resetFocus: () => {},
  projects: [],
  focus: false
}

export default SearchPanel
