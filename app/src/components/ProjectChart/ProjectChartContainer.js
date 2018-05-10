import React, { Component } from 'react'
import moment from 'moment'
import { Chart } from 'react-chartjs-2'
import * as qs from 'query-string'
import { compose, withState } from 'recompose'
import ProjectChartHeader from './ProjectChartHeader'
import ProjectChartFooter from './ProjectChartFooter'
import ProjectChart from './ProjectChart'
import ProjectChartMobile from './ProjectChartMobile'
import { normalizeData, makeItervalBounds } from './utils'

// Fix X mode in Chart.js lib. Monkey loves this.
const originalX = Chart.Interaction.modes.x
Chart.Interaction.modes.x = function (chart, e, options) {
  const activePoints = originalX.apply(this, arguments)
  return activePoints.reduce((acc, item) => {
    const i = acc.findIndex(x => x._datasetIndex === item._datasetIndex)
    if (i <= -1) {
      acc.push(item)
    }
    return acc
  }, [])
}

const getYAxisScale = scales => {
  for (const key in scales) {
    if (/^y-axis/.test(key)) {
      return scales[`${key}`]
    }
  }
  return scales['y-axis-1']
}

// Draw a vertical line in our Chart, when tooltip is activated.
Chart.defaults.LineWithLine = Chart.defaults.line
Chart.controllers.LineWithLine = Chart.controllers.line.extend({
  draw: function (ease) {
    Chart.controllers.line.prototype.draw.call(this, ease)

    if (this.chart.tooltip._active && this.chart.tooltip._active.length) {
      const activePoint = this.chart.tooltip._active[0]
      const ctx = this.chart.ctx
      const x = activePoint.tooltipPosition().x
      const scale = getYAxisScale(this.chart.scales)
      if (!scale) { return }
      const topY = scale.top
      const bottomY = scale.bottom

      ctx.save()
      ctx.beginPath()
      ctx.moveTo(x, topY)
      ctx.lineTo(x, bottomY)
      ctx.lineWidth = 1
      ctx.strokeStyle = '#adadad'
      ctx.stroke()
      ctx.restore()
    }
  }
})

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
        {this.props.isDesktop &&
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
          isERC20={this.props.isERC20}
          toggleEthPrice={this.props.toggleEthPrice}
          isToggledEthPrice={this.props.isToggledEthPrice}
          ethPrice={this.props.ethPrice}
          isDesktop={this.props.isDesktop}
        />}
        {this.props.isDesktop
          ? <ProjectChart
            {...this.props}
            setSelected={this.setSelected}
            isToggledBTC={this.state.isToggledBTC}
            history={this.props.price.history.items}
            burnRate={burnRate}
            from={this.state.startDate}
            to={this.state.endDate}
            transactionVolume={transactionVolume}
            ethSpentOverTimeByErc20Projects={this.props.ethSpentOverTime}
            isLoading={this.props.price.history.loading}
            isERC20={this.props.isERC20}
            isEmpty={this.props.price.history.items.length === 0} />
          : <ProjectChartMobile
            {...this.props}
          /> }
        {this.props.isDesktop &&
          <ProjectChartFooter
            {...this.props} /> }
      </div>
    )
  }
}

const enhance = compose(
  withState('isToggledMarketCap', 'toggleMarketcap', false),
  withState('isToggledGithubActivity', 'toggleGithubActivity', false),
  withState('isToggledEthSpentOverTime', 'toggleEthSpentOverTime', false),
  withState('isToggledVolume', 'toggleVolume', true),
  withState('isToggledTwitter', 'toggleTwitter', true),
  withState('isToggledBurnRate', 'toggleBurnRate', false),
  withState('isToggledTransactionVolume', 'toggleTransactionVolume', false),
  withState('isToggledEthPrice', 'toggleEthPrice', false),
  withState('isToggledEmojisSentiment', 'toggleEmojisSentiment', false),
  withState('isToggledDailyActiveAddresses', 'toggleActiveAddresses', false),
  withState('blockchainFilter', 'setBlockchainFilter', 'all')
)

export default enhance(ProjectChartContainer)
