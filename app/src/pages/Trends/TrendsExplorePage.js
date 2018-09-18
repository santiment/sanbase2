import React, { Component } from 'react'
import PropTypes from 'prop-types'
import * as qs from 'query-string'
import TimeFilter from './../../components/TimeFilter/TimeFilter'
import TrendsExploreHeader from '../../components/Trends/Explore/TrendsExploreHeader'
import TrendsExploreSourcesFilter from '../../components/Trends/Explore/TrendsExploreSourcesFilter'
import {
  validateSearchSources,
  Source
} from '../../components/Trends/trendsUtils'
import GetTrends from './../../components/Trends/GetTrends'
import GetTimeSeries from './../../components/GetTimeSeries'
import TrendsReChart from './../../components/Trends/TrendsReChart'
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
    const { timeFilter } = this.state
    return (
      <div className='TrendsExplorePage'>
        <div className='TrendsExplorePage__content'>
          <TrendsExploreHeader topic={match.params.topic} />
          <TimeFilter
            timeOptions={['1w', '1m', '3m', '6m', '1y', 'all']}
            onSelectOption={this.handleSourceSelect}
            defaultSelected='6m'
          />
          <GetTrends
            topic={match.params.topic}
            render={trends => (
              <GetTimeSeries
                price={{
                  from: timeFilter,
                  interval: '1d'
                }}
                render={({ timeseries }) => (
                  <div style={{ minHeight: 300 }}>
                    <TrendsReChart data={timeseries.price} trends={trends} />
                  </div>
                )}
              />
            )}
          />
        </div>
      </div>
    )
  }

  handleSourceSelect = timeFilter => {
    this.setState({ timeFilter }, this.updateSearchQuery)
  }

  mapStateToQS = ({ timeFilter }) =>
    '?' + qs.stringify({ timeFilter }, { arrayFormat: 'bracket' })

  updateSearchQuery = () => {
    this.props.history.push({
      search: this.mapStateToQS(this.state)
    })
  }
}

export const getStateFromQS = ({ location }) => {
  const { timeFilter, source } = qs.parse(location.search, {
    arrayFormat: 'bracket'
  })

  return {
    timeFilter: timeFilter || '6m'
  }
}

export default TrendsExplorePage
