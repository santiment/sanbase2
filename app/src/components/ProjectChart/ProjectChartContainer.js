import React, { Component } from 'react'
import moment from 'moment'
import * as qs from 'query-string'
import {
  compose,
  withState
} from 'recompose'
import ProjectChartHeader from './ProjectChartHeader'
import ProjectChartFooter from './ProjectChartFooter'
import ProjectChart from './ProjectChart'
import { normalizeData, makeItervalBounds } from './utils'

class ProjectChartContainer extends Component {
  constructor (props) {
    super(props)
    const shareableState = qs.parse(props.location.search)
    const { from, to } = makeItervalBounds('all')
    this.state = {
      interval: 'all',
      isError: false,
      errorMessage: '',
      selected: undefined,
      startDate: moment(from),
      endDate: moment(to),
      focusedInput: null,
      isToggledBTC: shareableState.currency && shareableState.currency === 'BTC'
    }
    this.props.toggleVolume(shareableState.volume)
    this.props.toggleMarketcap(shareableState.marketcap)
    this.props.toggleGithubActivity(shareableState.github)
    this.props.toggleTwitter(shareableState.twitter)
    this.props.toggleBurnRate(shareableState.tbr)
    this.props.toggleTransactionVolume(shareableState.tv)

    this.setFilter = this.setFilter.bind(this)
    this.setSelected = this.setSelected.bind(this)
    this.onDatesChange = this.onDatesChange.bind(this)
    this.onFocusChange = this.onFocusChange.bind(this)
    this.updateHistoryData = this.updateHistoryData.bind(this)
    this.toggleBTC = this.toggleBTC.bind(this)
  }

  onFocusChange (focusedInput) {
    this.setState({
      focusedInput: focusedInput
    })
  }

  onDatesChange (startDate, endDate) {
    this.setState({
      startDate,
      endDate
    })
    if (!startDate || !endDate) { return }
    this.setState({
      interval: undefined
    })
    let interval = '1h'
    const diffInDays = moment(endDate).diff(startDate, 'days')
    if (diffInDays > 32 && diffInDays < 900) {
      interval = '1d'
    } else if (diffInDays >= 900) {
      interval = '1w'
    }
    this.props.onDatesChange(
      startDate.utc().format(),
      endDate.utc().format(),
      interval,
      this.props.ticker
    )
  }

  setSelected (selected) {
    this.setState({selected})
  }

  setFilter (interval) {
    if (interval === this.state.interval) { return }
    this.setState({
      interval
    }, () => {
      this.updateHistoryData(this.props.ticker)
    })
  }

  toggleBTC (isToggledBTC) {
    this.setState({isToggledBTC})
  }

  updateHistoryData (ticker) {
    const { interval } = this.state
    const { from, to, minInterval } = makeItervalBounds(interval)
    this.setState({
      interval,
      startDate: moment(from),
      endDate: moment(to)
    })
    this.props.onDatesChange(from, to, minInterval, ticker)
  }

  componentWillReceiveProps (nextProps) {
    if (nextProps.ticker !== this.props.ticker) {
      this.setState({
        interval: '1m'
      })
      this.updateHistoryData(nextProps.ticker)
    }
  }

  componentDidMount () {
    const { ticker } = this.props
    const shareableState = qs.parse(this.props.location.search)
    if (shareableState.from && shareableState.to) {
      this.onDatesChange(moment(shareableState.from), moment(shareableState.to))
    } else {
      this.updateHistoryData(ticker)
    }
  }

  render () {
    const newShareableState = {
      volume: this.props.isToggledVolume,
      marketcap: this.props.isToggledMarketCap,
      github: this.props.isToggledGithubActivity,
      twitter: this.props.isToggledTwitter,
      tbr: this.props.isToggledBurnRate,
      tv: this.props.isToggledTransactionVolume,
      currency: this.state.isToggledBTC ? 'BTC' : 'USD',
      from: moment(this.state.startDate).utc().format(),
      to: moment(this.state.endDate).utc().format()
    }
    let fullpath = window.location.href
    if (window.location.href.indexOf('?') > -1) {
      fullpath = window.location.href.split('?')[0]
    }
    const shareableURL = fullpath + '?' + qs.stringify(newShareableState)
    const burnRate = {
      ...this.props.burnRate,
      items: normalizeData({
        data: this.props.burnRate.items,
        fieldName: 'burnRate',
        filter: this.props.blockchainFilter
      })
    }
    const transactionVolume = {
      ...this.props.transactionVolume,
      items: normalizeData({
        data: this.props.transactionVolume.items,
        fieldName: 'transactionVolume',
        filter: this.props.blockchainFilter
      })
    }
    return (
      <div className='project-dp-chart'>
        <ProjectChartHeader
          startDate={this.state.startDate}
          endDate={this.state.endDate}
          changeDates={this.onDatesChange}
          focusedInput={this.state.focusedInput}
          onFocusChange={this.onFocusChange}
          setFilter={this.setFilter}
          toggleBTC={this.toggleBTC}
          isToggledBTC={this.state.isToggledBTC}
          interval={this.state.interval}
          shareableURL={shareableURL}
          ticker={this.props.ticker}
          isDesktop={this.props.isDesktop}
        />
        <ProjectChart
          {...this.props}
          setSelected={this.setSelected}
          isToggledBTC={this.state.isToggledBTC}
          history={this.props.price.history.items}
          burnRate={burnRate}
          transactionVolume={transactionVolume}
          isLoading={this.props.price.history.loading}
          isEmpty={this.props.price.history.items.length === 0} />
        <ProjectChartFooter {...this.props} />
      </div>
    )
  }
}

const enhance = compose(
  withState('isToggledMarketCap', 'toggleMarketcap', false),
  withState('isToggledGithubActivity', 'toggleGithubActivity', false),
  withState('isToggledVolume', 'toggleVolume', true),
  withState('isToggledTwitter', 'toggleTwitter', false),
  withState('isToggledBurnRate', 'toggleBurnRate', false),
  withState('isToggledTransactionVolume', 'toggleTransactionVolume', false),
  withState('blockchainFilter', 'setBlockchainFilter', 'all')
)

export default enhance(ProjectChartContainer)
