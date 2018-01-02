import React, { Component } from 'react'
import { withApollo } from 'react-apollo'
import gql from 'graphql-tag'
import moment from 'moment'
import ProjectChart from './ProjectChart'

const getHistoryGQL = gql`
  query history($ticker: String, $from: DateTime, $to: DateTime, $interval: String) {
    historyPrice(
      ticker: $ticker,
      from: $from,
      to: $to,
      interval: $interval
    ) {
      priceBtc,
      priceUsd,
      volume,
      datetime,
      marketcap
    }
}`

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

const fetchPriceHistoryFromStartToEndDate = (
  client,
  ticker,
  startDate,
  endDate,
  minInterval = '1h'
) => {
  return new Promise((resolve, reject) => {
    client.query({
      query: getHistoryGQL,
      variables: {
        'ticker': ticker,
        'from': moment(startDate).utc(),
        'to': moment(endDate).utc(),
        'interval': minInterval
      }
    })
    .then(response => {
      resolve(response.data)
    })
    .catch(error => reject(error))
  })
}

const fetchPriceHistory = (client, ticker, interval = '1m') => {
  const { from, to, minInterval } = makeItervalBounds(interval)
  return new Promise((resolve, reject) => {
    client.query({
      query: getHistoryGQL,
      variables: {
        'ticker': ticker,
        'from': from,
        'to': to,
        'interval': minInterval
      }
    })
    .then(response => {
      resolve(response.data)
    })
    .catch(error => reject(error))
  })
}

class ProjectChartContainer extends Component {
  constructor (props) {
    super(props)
    const { from, to } = makeItervalBounds('1m')
    this.state = {
      interval: '1m',
      isLoading: true,
      isError: false,
      isEmpty: true,
      errorMessage: '',
      selected: undefined,
      history: [],
      startDate: moment(from),
      endDate: moment(to),
      focusedInput: null
    }

    this.setFilter = this.setFilter.bind(this)
    this.setSelected = this.setSelected.bind(this)
    this.onDatesChange = this.onDatesChange.bind(this)
    this.onFocusChange = this.onFocusChange.bind(this)
  }

  onFocusChange (focusedInput) {
    if (focusedInput) {
      this.setState({
        focusedInput: focusedInput
      })
      return
    }
    const { client, ticker } = this.props
    const { startDate, endDate } = this.state
    //this.setState({
      //interval: undefined,
      //isLoading: true,
      //selected: undefined,
      //focusedInput: focusedInput
    //})
    console.log(startDate, endDate)
    //fetchPriceHistoryFromStartToEndDate(client, ticker, startDate, endDate).then(data => {
      //const historyPrice = data.historyPrice || []
      //this.setState({
        //isLoading: false,
        //isEmpty: historyPrice.length === 0,
        //history: data.historyPrice,
        //selected: undefined,
        //startDate: startDate,
        //endDate: endDate
      //})
    //})
  }

  onDatesChange (startDate, endDate) {
    this.setState({startDate, endDate})
  }

  setSelected (selected) {
    this.setState({selected})
  }

  setFilter (interval) {
    if (interval === this.state.interval) { return }
    const { client, ticker } = this.props
    const { from, to } = makeItervalBounds(interval)
    this.setState({
      interval,
      isLoading: true,
      selected: undefined,
      startDate: moment(from),
      endDate: moment(to)
    })
    fetchPriceHistory(client, ticker, interval).then(data => {
      const historyPrice = data.historyPrice || []
      this.setState({
        isLoading: false,
        isEmpty: historyPrice.length === 0,
        history: data.historyPrice
      })
    })
  }

  componentDidMount () {
    const { client, ticker } = this.props
    const { interval } = this.state
    fetchPriceHistory(client, ticker, interval).then(data => {
      const historyPrice = data.historyPrice || []
      this.setState({
        isLoading: false,
        isEmpty: historyPrice.length === 0,
        history: data.historyPrice
      })
    })
    .catch(error => console.log(error))
  }

  render () {
    const { isEmpty, isLoading } = this.state.history
    return (
      <div style={{width: '100%'}}>
        {!isLoading && isEmpty
          ? 'We can\'t find any project with such ticker symbol.'
          : <ProjectChart
            setFilter={this.setFilter}
            setSelected={this.setSelected}
            changeDates={this.onDatesChange}
            onFocusChange={this.onFocusChange}
            {...this.state} />}
      </div>
    )
  }
}

export default withApollo(ProjectChartContainer)
