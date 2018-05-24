import React, { Component } from 'react'
import { connect } from 'react-redux'
import cx from 'classnames'
import moment from 'moment'
import { Button } from 'semantic-ui-react'
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
    const shareableState = ((shareable) => {
      Object.keys(shareable).forEach(key => {
        shareable[`${key}`] = shareable[key] === 'true'
      })
      return shareable
    })(qs.parse(props.location.search))
    const { from, to } = makeItervalBounds('all')
    this.state = {
      interval: 'all',
      isError: false,
      errorMessage: '',
      selected: undefined,
      startDate: moment(shareableState.from) || moment(from),
      endDate: moment(shareableState.from) || moment(to),
      focusedInput: null,
      isToggledBTC: shareableState.currency && shareableState.currency === 'BTC'
    }

    if (Object.keys(shareableState).length > 0) {
      this.props.toggleVolume(shareableState.volume)
      this.props.toggleMarketcap(shareableState.marketcap)
      this.props.toggleGithubActivity(shareableState.github)
      this.props.toggleTwitter(shareableState.twitter)
      this.props.toggleBurnRate(shareableState.tbr)
      this.props.toggleTransactionVolume(shareableState.tv)
      this.props.toggleActiveAddresses(shareableState.daa)
      this.props.toggleEthSpentOverTime(shareableState.ethSpent)
      this.props.toggleEthPrice(shareableState.ethPrice)
    }

    this.setFilter = this.setFilter.bind(this)
    this.setSelected = this.setSelected.bind(this)
    this.onFocusChange = this.onFocusChange.bind(this)
    this.toggleBTC = this.toggleBTC.bind(this)
    this.setFromTo = this.setFromTo.bind(this)
  }

  onFocusChange (focusedInput) {
    this.setState({
      focusedInput: focusedInput
    })
  }

  setSelected (selected) {
    this.setState({selected})
  }

  setFromTo (from, to) {
    if (!moment.isMoment(from) || !moment.isMoment(to)) {
      return
    }
    let interval = '1w'
    const diffInDays = moment(to).diff(from, 'days')
    if (diffInDays > 32 && diffInDays < 900) {
      interval = '1d'
    } else if (diffInDays >= 900) {
      interval = '1w'
    } else if (diffInDays > 1 && diffInDays <= 7) {
      interval = '1h'
    } else if (diffInDays < 0) {
      interval = '5m'
    }
    this.props.changeTimeFilter({
      to: to.utc().format(),
      from: from.utc().format(),
      interval,
      timeframe: undefined
    })
  }

  setFilter (timeframe) {
    const { from, to, minInterval } = makeItervalBounds(timeframe)
    let interval = minInterval
    const diffInDays = moment(to).diff(from, 'days')
    if (diffInDays > 32 && diffInDays < 900) {
      interval = '1d'
    } else if (diffInDays >= 900) {
      interval = '1w'
    }
    this.props.changeTimeFilter({
      timeframe,
      to,
      from,
      interval
    })
  }

  toggleBTC (isToggledBTC) {
    this.setState({isToggledBTC})
  }

  componentWillReceiveProps (nextProps) {
    if (nextProps.ticker !== this.props.ticker &&
      typeof this.props.ticker !== 'undefined') {
      this.setFilter('all')
      this.props.toggleVolume(true)
      this.props.toggleMarketcap(false)
      this.props.toggleGithubActivity(false)
      this.props.toggleTwitter(false)
      this.props.toggleBurnRate(false)
      this.props.toggleTransactionVolume(false)
      this.props.toggleActiveAddresses(false)
      this.props.toggleEthSpentOverTime(false)
      this.props.toggleEthPrice(false)
    }
  }

  componentDidMount () {
    const {from, to, timeframe} = qs.parse(this.props.location.search)
    if (timeframe) {
      this.setFilter(timeframe)
    }
    if (from && to && !timeframe) {
      this.setFromTo(moment(from), moment(to))
    }
    if (!from && !to && !timeframe) {
      this.setFilter('all')
    }
  }

  render () {
    const newShareableState = {
      volume: this.props.isToggledVolume || undefined,
      marketcap: this.props.isToggledMarketCap || undefined,
      github: this.props.isToggledGithubActivity || undefined,
      twitter: this.props.isToggledTwitter || undefined,
      tbr: this.props.isToggledBurnRate || undefined,
      tv: this.props.isToggledTransactionVolume || undefined,
      daa: this.props.isToggledDailyActiveAddresses || undefined,
      ethSpent: this.props.isToggledEthSpentOverTime || undefined,
      ethPrice: this.props.isToggledEthPrice || undefined,
      currency: this.state.isToggledBTC ? 'BTC' : 'USD',
      from: this.props.timeFilter.from || undefined,
      to: this.props.timeFilter.to || undefined,
      timeframe: this.props.timeFilter.timeframe || undefined
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
      <div className={cx({
        'project-dp-chart': true
      })} >
        {(this.props.isDesktop || this.props.isFullscreenMobile) &&
        <ProjectChartHeader
          from={this.props.timeFilter.from}
          to={this.props.timeFilter.to}
          setFromTo={this.setFromTo}
          focusedInput={this.state.focusedInput}
          onFocusChange={this.onFocusChange}
          setFilter={this.setFilter}
          toggleBTC={this.toggleBTC}
          isToggledBTC={this.state.isToggledBTC}
          interval={this.props.timeFilter.timeframe}
          shareableURL={shareableURL}
          ticker={this.props.ticker}
          isERC20={this.props.isERC20}
          isDesktop={this.props.isDesktop}
        />}
        {(this.props.isDesktop || this.props.isFullscreenMobile)
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
        {(this.props.isDesktop || this.props.isFullscreenMobile) &&
          <ProjectChartFooter {...this.props} />}
        {this.props.isFullscreenMobile &&
          <Button onClick={this.props.toggleFullscreen} basic >
            Back to newest mode
          </Button>}
      </div>
    )
  }
}

const mapStateToProps = state => {
  return {
    isFullscreenMobile: state.detailedPageUi.isFullscreenMobile,
    timeFilter: state.detailedPageUi.timeFilter
  }
}

const mapDispatchToProps = dispatch => {
  return {
    toggleFullscreen: () => {
      dispatch({
        type: 'TOGGLE_FULLSCREEN_MOBILE'
      })
    },
    changeTimeFilter: ({timeframe, from, to, interval}) => {
      dispatch({
        type: 'CHANGE_TIME_FILTER',
        timeframe,
        from,
        to,
        interval
      })
    }
  }
}

const enhance = compose(
  connect(mapStateToProps, mapDispatchToProps),
  withState('isToggledMarketCap', 'toggleMarketcap', false),
  withState('isToggledGithubActivity', 'toggleGithubActivity', false),
  withState('isToggledEthSpentOverTime', 'toggleEthSpentOverTime', false),
  withState('isToggledVolume', 'toggleVolume', true),
  withState('isToggledTwitter', 'toggleTwitter', false),
  withState('isToggledBurnRate', 'toggleBurnRate', false),
  withState('isToggledTransactionVolume', 'toggleTransactionVolume', false),
  withState('isToggledEthPrice', 'toggleEthPrice', false),
  withState('isToggledEmojisSentiment', 'toggleEmojisSentiment', false),
  withState('isToggledDailyActiveAddresses', 'toggleActiveAddresses', false),
  withState('blockchainFilter', 'setBlockchainFilter', 'all')
)

export default enhance(ProjectChartContainer)
