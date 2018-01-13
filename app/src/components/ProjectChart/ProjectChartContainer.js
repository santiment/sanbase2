import React, { Component } from 'react'
import moment from 'moment'
import ProjectChart from './ProjectChart'

export const makeItervalBounds = interval => {
  switch (interval) {
    case '1d':
      return {
        from: moment().subtract(1, 'd').utc().format('YYYY-MM-DD') + 'T00:00:00Z',
        to: moment().utc().format(),
        minInterval: '5m'
      }
    case '1w':
      return {
        from: moment().subtract(1, 'weeks').utc().format(),
        to: moment().utc().format(),
        minInterval: '1h'
      }
    case '2w':
      return {
        from: moment().subtract(2, 'weeks').utc().format(),
        to: moment().utc().format(),
        minInterval: '1h'
      }
    default:
      return {
        from: moment().subtract(1, 'months').utc().format(),
        to: moment().utc().format(),
        minInterval: '1h'
      }
  }
}

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
      focusedInput: null
    }

    this.setFilter = this.setFilter.bind(this)
    this.setSelected = this.setSelected.bind(this)
    this.onDatesChange = this.onDatesChange.bind(this)
    this.onFocusChange = this.onFocusChange.bind(this)
    this.updateHistoryData = this.updateHistoryData.bind(this)
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
      <div style={{width: '100%'}}>
        <ProjectChart
          setFilter={this.setFilter}
          setSelected={this.setSelected}
          changeDates={this.onDatesChange}
          onFocusChange={this.onFocusChange}
          twitter={this.props.twitter}
          github={this.props.github}
          burnRate={this.props.burnRate}
          history={this.props.price.history.items}
          isLoading={this.props.price.history.loading}
          isEmpty={this.props.price.history.items.length === 0}
          {...this.state} />
      </div>
    )
  }
}

export default ProjectChartContainer
