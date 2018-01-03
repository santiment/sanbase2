import React, { Component } from 'react'
import PropTypes from 'prop-types'
import { Search, Input } from 'semantic-ui-react'
import './Search.css'

const resultRenderer = ({ name, ticker }) => {
  return (
    <div>{name} ({ticker})</div>
  )
}

const CustomInput = <Input
  iconPosition={'left'}
  placeholder='Search...' />

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
  }

  handleResultSelect (e, { result }) {
    this.setState({ value: '' })
    this.props.onSelectProject(result.ticker)
  }

  handleSearchChange (e, { value }) {
    this.setState({ isLoading: true, value })

    const results = this.props.projects.filter(el => {
      const name = el.name || ''
      const ticker = el.ticker || ''
      return name.toLowerCase().indexOf(value.toLowerCase()) !== -1 ||
        ticker.toLowerCase().indexOf(value.toLowerCase()) !== -1
    }).map((el, index) => {
      return {
        name: el.name,
        ticker: el.ticker,
        key: index
      }
    })

    this.setState({
      isLoading: false,
      results: results
    })
  }

  render () {
    return (
      <div className='search-panel'>
        <Search
          key={'search'}
          loading={this.state.isLoading}
          onResultSelect={this.handleResultSelect}
          onSearchChange={this.handleSearchChange}
          results={this.state.results}
          value={this.state.value}
          resultRenderer={resultRenderer}
          selectFirstResult
          input={CustomInput}
        />
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
