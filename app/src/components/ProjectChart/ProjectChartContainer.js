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
  state = {
    interval: '1m',
    isLoading: true,
    isError: false,
    isEmpty: true,
    errorMessage: '',
    selected: null,
    history: []
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
            {...this.state} />}
      </div>
    )
  }

  setSelected = selected => {
    this.setState({selected})
  }

  setFilter = interval => {
    if (interval === this.state.interval) { return }
    const { client, ticker } = this.props
    this.setState({
      interval,
      isLoading: true,
      selected: null
    })
    fetchPriceHistory(client, ticker, interval).then(data => {
      const historyPrice = data.historyPrice || []
      this.setState({
        isLoading: false,
        isEmpty: historyPrice.length === 0,
        history: data.historyPrice,
        selected: null
      })
    })
  }
}

export default withApollo(ProjectChartContainer)
