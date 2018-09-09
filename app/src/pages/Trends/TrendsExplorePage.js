import React, { Component } from 'react'
import PropTypes from 'prop-types'
import * as qs from 'query-string'
import TrendsExploreChart from '../../components/Trends/Explore/TrendsExploreChart'
import TimeFilter from './../../components/TimeFilter/TimeFilter'
import TrendsExploreHeader from '../../components/Trends/Explore/TrendsExploreHeader'
import TrendsExploreSourcesFilter from '../../components/Trends/Explore/TrendsExploreSourcesFilter'
import {
  validateSearchSources,
  Source
} from '../../components/Trends/trendsUtils'
import GetTrends from './../../components/Trends/GetTrends'
import './TrendsExplorePage.css'

export class TrendsExplorePage extends Component {
  state = {
    ...getStateFromQS(this.props)
  }

  static defaultProps = {
    match: { params: {} },
    location: {},
    history: {}
  }

  static propTypes = {
    match: PropTypes.object,
    location: PropTypes.object,
    history: PropTypes.object
  }

  static getDerivedStateFromProps (nextProps, prevState) {
    return {
      ...getStateFromQS(nextProps)
    }
  }

  render () {
    const { match, isDesktop } = this.props
    const { selectedSources } = this.state
    return (
      <div className='TrendsExplorePage'>
        <div className='TrendsExplorePage__content'>
          <TrendsExploreHeader
            topic={match.params.topic}
            selectedSources={selectedSources}
          />
          <TimeFilter
            timeOptions={['1w', '1m', '3m', '6m', '1y', 'all']}
            defaultSelected='6m'
            disabled
          />
          <GetTrends
            topic={match.params.topic}
            render={props => (
              <TrendsExploreChart
                {...props}
                isDesktop={isDesktop}
                selectedSources={selectedSources}
              />
            )}
          />
          <TrendsExploreSourcesFilter
            selectedSources={selectedSources}
            handleSourceSelect={this.handleSourceSelect}
          />
        </div>
      </div>
    )
  }

  handleSourceSelect = ({ currentTarget }) => {
    const { selectedSources } = this.state
    const source = currentTarget.dataset.source
    const newSelectedSource = calculateNewSources({
      source,
      selectedSources,
      sources: Object.keys(Source)
    })

    this.setState(
      {
        selectedSources: newSelectedSource
      },
      this.updateSearchQuery
    )
  }

  mapStateToQS = ({ interval, selectedSources }) =>
    '?' +
    qs.stringify(
      { interval, source: selectedSources },
      { arrayFormat: 'bracket' }
    )

  updateSearchQuery = () => {
    this.props.history.push({
      search: this.mapStateToQS(this.state)
    })
  }
}

export const getStateFromQS = ({ location }) => {
  const { interval, source } = qs.parse(location.search, {
    arrayFormat: 'bracket'
  })

  return {
    interval: interval || '6m',
    selectedSources: validateSearchSources(source)
  }
}

export const calculateNewSources = ({
  source,
  selectedSources = ['merged'],
  sources
}) => {
  if (source === 'merged') {
    if (selectedSources.includes('merged')) {
      return sources.filter(selectedSource => selectedSource !== 'merged')
    } else {
      return ['merged']
    }
  } else {
    if (selectedSources.includes(source)) {
      if (selectedSources.length === 1) {
        return ['merged']
      }
      return selectedSources.filter(selectedSource => selectedSource !== source)
    } else {
      return [...selectedSources, source]
    }
  }
}

export default TrendsExplorePage
