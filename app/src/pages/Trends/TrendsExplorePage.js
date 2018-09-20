import React, { Component } from 'react'
import PropTypes from 'prop-types'
import * as qs from 'query-string'
import TimeFilter from './../../components/TimeFilter/TimeFilter'
import TrendsExploreHeader from '../../components/Trends/Explore/TrendsExploreHeader'
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
    const { match } = this.props
    const { timeFilter, assetSlug } = this.state
    return (
      <div className='TrendsExplorePage'>
        <div className='TrendsExplorePage__content'>
          <TrendsExploreHeader topic={match.params.topic} />
          <div className='TrendsExplorePage__settings'>
            <TimeFilter
              timeOptions={['1w', '1m', '3m', '6m']}
              onSelectOption={this.handleSelectTimeFilter}
              defaultSelected={timeFilter}
            />
            <span>
              Compared to <strong>BTC/USD</strong>
            </span>
          </div>
          <GetTrends
            topic={match.params.topic}
            timeFilter={timeFilter}
            interval={'1d'}
            render={trends => (
              <GetTimeSeries
                price={{
                  timeFilter,
                  slug: assetSlug,
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

  handleSelectTimeFilter = timeFilter => {
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
  const { timeFilter } = qs.parse(location.search, {
    arrayFormat: 'bracket'
  })

  return {
    timeFilter: timeFilter || '3m',
    assetSlug: 'bitcoin'
  }
}

export default TrendsExplorePage
