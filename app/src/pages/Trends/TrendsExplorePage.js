import React, { Component } from 'react'
import queryString from 'query-string'
import { graphql } from 'react-apollo'
import moment from 'moment'
import { trendsExploreGQL } from '../../components/Trends/trendsExploreGQL'
import TrendsExploreChart from '../../components/Trends/Explore/TrendsExploreChart'
import TimeFilter from './../../components/TimeFilter/TimeFilter'
import TrendsExploreHeader from '../../components/Trends/Explore/TrendsExploreHeader'
import TrendsExploreSourcesFilter from '../../components/Trends/Explore/TrendsExploreSourcesFilter'
import {
  parseTrendsGQLProps,
  validateSearchSources,
  Source
} from '../../components/Trends/trendsUtils'
import './TrendsExplorePage.css'

export class TrendsExplorePage extends Component {
  state = this.parseSearchQuerySourcesToState()

  parseSearchQuerySourcesToState () {
    const { location } = this.props
    const { interval, source } = queryString.parse(location.search, {
      arrayFormat: 'bracket'
    })

    return {
      interval: interval || '6m',
      selectedSources: validateSearchSources(source)
    }
  }

  formatStateToSearchQuery () {
    const { interval, selectedSources } = this.state

    return (
      '?' +
      queryString.stringify(
        {
          interval,
          source: selectedSources
        },
        { arrayFormat: 'bracket' }
      )
    )
  }

  handleSourceSelect = ({ currentTarget }) => {
    console.log(this.props)
    console.log(currentTarget.dataset.source)
    const { selectedSources } = this.state
    const source = currentTarget.dataset.source
    let newSelectedSources

    if (source === 'merged') {
      if (selectedSources.includes('merged')) {
        newSelectedSources = Object.keys(Source).filter(
          selectedSource => selectedSource !== 'merged'
        )
      } else {
        newSelectedSources = ['merged']
      }
    } else {
      if (selectedSources.includes(source)) {
        if (selectedSources.length === 1) return
        newSelectedSources = selectedSources.filter(
          selectedSource => selectedSource !== source
        )
      } else {
        newSelectedSources = [...selectedSources, source]
      }
    }

    this.setState(prevState => ({
      ...prevState,
      selectedSources: newSelectedSources
    }))
    this.updateSearchQuery()
  }

  updateSearchQuery () {
    // HACK
    // FIX: PASS ARGUMENT STATE
    setTimeout(
      () => this.props.history.push(this.formatStateToSearchQuery()),
      0
    )
  }

  render () {
    const { sources, match, isDesktop } = this.props
    const { selectedSources } = this.state
    return (
      <div className='TrendsExplorePage'>
        <div className='TrendsExplorePage__content'>
          <TrendsExploreHeader topic={match.params.topic} />
          <TimeFilter
            timeOptions={['1w', '1m', '3m', '6m', '1y', 'all']}
            defaultSelected='6m'
            disabled
          />
          <TrendsExploreChart sources={sources} isDesktop={isDesktop} />
          <TrendsExploreSourcesFilter
            selectedSources={selectedSources}
            handleSourceSelect={this.handleSourceSelect}
          />
        </div>
      </div>
    )
  }
}

export default graphql(trendsExploreGQL, {
  props: parseTrendsGQLProps,
  options: ({ match }) => {
    return {
      variables: {
        searchText: match.params.topic,
        from: moment()
          .utc()
          .subtract(6, 'months')
          .format()
      }
    }
  }
})(TrendsExplorePage)
