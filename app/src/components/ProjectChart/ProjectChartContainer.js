import React, { Component } from 'react'
import moment from 'moment'
import {
  compose,
  withState
} from 'recompose'
import ProjectChartHeader from './ProjectChartHeader'
import ProjectChartFooter from './ProjectChartFooter'
import ProjectChart from './ProjectChart'
import { makeItervalBounds } from './utils'

class ProjectChartContainer extends Component {
  constructor (props) {
    super(props)
    const { from, to } = makeItervalBounds('1m')
    this.state = {
      interval: '1m',
      isError: false,
      errorMessage: '',
      selected: undefined,
      startDate: moment(from),
      endDate: moment(to),
      focusedInput: null,
      isToggledBTC: false
    }

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
    this.updateHistoryData(ticker)
  }

  render () {
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
          interval={this.state.interval} />
        <ProjectChart
          setSelected={this.setSelected}
          isToggledBTC={this.state.isToggledBTC}
          twitter={this.props.twitter}
          github={this.props.github}
          burnRate={this.props.burnRate}
          transactionVolume={this.props.transactionVolume}
          history={this.props.price.history.items}
          isLoading={this.props.price.history.loading}
          isEmpty={this.props.price.history.items.length === 0}
          {...this.props} />
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
  withState('isToggledTransactionVolume', 'toggleTransactionVolume', false)
)

export default enhance(ProjectChartContainer)
