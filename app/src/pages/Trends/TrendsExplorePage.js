import React, { Component } from 'react'
import PropTypes from 'prop-types'
import * as qs from 'query-string'
import Selector from './../../components/Selector/Selector'
import TrendsExploreHeader from '../../components/Trends/Explore/TrendsExploreHeader'
import GetTrends from './../../components/Trends/GetTrends'
import GetTimeSeries from './../../components/GetTimeSeries'
import TrendsReChart from './../../components/Trends/TrendsReChart'
import { capitalizeStr } from './../../utils/utils'
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
    const { timeRange, asset } = this.state
    return (
      <div className='TrendsExplorePage'>
        <div className='TrendsExplorePage__content'>
          <TrendsExploreHeader topic={match.params.topic} />
          <div className='TrendsExplorePage__settings'>
            <Selector
              options={['1w', '1m', '3m', '6m']}
              onSelectOption={this.handleSelectTimeRange}
              defaultSelected={timeRange}
            />
            <Selector
              options={['bitcoin', 'ethereum']}
              nameOptions={['BTC/USD', 'ETH/USD']}
              onSelectOption={this.handleSelectAsset}
              defaultSelected={asset}
            />
          </div>
          <GetTrends
            topic={match.params.topic}
            timeRange={timeRange}
            interval={'1d'}
            render={trends => (
              <GetTimeSeries
                price={{
                  timeRange,
                  slug: asset,
                  interval: '1d'
                }}
                render={({ timeseries }) => (
                  <div style={{ minHeight: 300 }}>
                    <TrendsReChart
                      asset={capitalizeStr(asset)}
                      data={timeseries.price}
                      trends={trends}
                    />
                  </div>
                )}
              />
            )}
          />
        </div>
      </div>
    )
  }

  handleSelectTimeRange = timeRange => {
    this.setState({ timeRange }, this.updateSearchQuery)
  }

  handleSelectAsset = asset => {
    this.setState({ asset }, this.updateSearchQuery)
  }

  mapStateToQS = ({ timeRange, asset }) =>
    '?' + qs.stringify({ timeRange, asset }, { arrayFormat: 'bracket' })

  updateSearchQuery = () => {
    this.props.history.push({
      search: this.mapStateToQS(this.state)
    })
  }
}

export const getStateFromQS = ({ location }) => {
  const { timeRange, asset } = qs.parse(location.search, {
    arrayFormat: 'bracket'
  })

  return {
    timeRange: timeRange || '3m',
    asset: asset || 'bitcoin'
  }
}

export default TrendsExplorePage
