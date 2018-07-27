import React from 'react'
import PropTypes from 'prop-types'
import { Message, Label } from 'semantic-ui-react'
import { graphql } from 'react-apollo'
import { compose, withProps } from 'recompose'
import moment from 'moment'
import { HistoryPriceGQL } from './../pages/Detailed/DetailedGQL'
import PercentChanges from './PercentChanges'
import PostVisualBacktestChart from './PostVisualBacktestChart'

const getChanges = (start, last, prop = 'priceUsd') =>
  (last[`${prop}`] - start[`${prop}`]) / start[`${prop}`] * 100

const isTotalMarket = ticker => ticker === 'Crypto Market'

const binarySearchIndex = (list, value, predicate) => {
  let start = 0
  let stop = list.length - 1
  let middle = Math.floor((start + stop) / 2)

  while (start < stop) {
    const searchResult = predicate(list[middle], value)
    // console.log(searchResult)

    if (searchResult < 0) {
      stop = middle - 1
    } else {
      start = middle + 1
    }

    middle = Math.floor((start + stop) / 2)
  }

  return middle
}

const isDatetimeSameDay = (item, value) => {
  // console.log(item, value)
  const itemDate = moment(item.datetime).utc()
  const valueDate = moment(value)
  // console.log(
  //   itemDate.calendar(),
  //   valueDate.calendar(),
  //   itemDate.isSame(valueDate)
  // )
  // console.log(itemDate.date(), moment(value).date())
  // console.log(itemDate.day(), moment(value).day())
  return itemDate.isBefore(valueDate) ? 1 : -1
}

const propTypes = {
  ticker: PropTypes.string.isRequired,
  history: PropTypes.object
}

export const PostVisualBacktest = ({
  ticker,
  change,
  changeProp,
  changePriceProp,
  history,
  from,
  postCreationDateInfo = {}
}) => {
  if (!change) return null
  // const
  return (
    <Message>
      <Label horizontal>{ticker}</Label>
      {changeProp} changes after publication
      {change && <PercentChanges changes={change} />}
      <PostVisualBacktestChart
        history={history}
        postCreationDateInfo={postCreationDateInfo}
        changePriceProp={changePriceProp}
      />
    </Message>
  )
}

const enhance = compose(
  graphql(HistoryPriceGQL, {
    name: 'history',
    options: ({ ticker, from }) => {
      return {
        skip: !ticker || !from,
        errorPolicy: 'all',
        variables: {
          from: moment(from)
            .subtract(6, 'months')
            .utc()
            .format(),
          ticker: isTotalMarket(ticker) ? 'TOTAL_MARKET' : ticker
        }
      }
    }
  }),
  withProps(({ ticker, history = {}, from }) => {
    const { historyPrice } = history
    if (!historyPrice || historyPrice.length === 0) return {}
    // console.log(from, historyPrice)
    // console.log(binarySearchIndex(historyPrice, from, isDatetimeSameDay), from)
    // console.log(historyPrice)
    const start =
      historyPrice[binarySearchIndex(historyPrice, from, isDatetimeSameDay)]
    const last = historyPrice[historyPrice.length - 1]
    if (!start || !last) return {}
    const changeProp = isTotalMarket(ticker) ? 'Total marketcap' : 'Prices'
    const changePriceProp = isTotalMarket(ticker) ? 'marketcap' : 'priceUsd'
    return {
      change: getChanges(start, last, changePriceProp),
      changeProp,
      changePriceProp,
      postCreationDateInfo: start
    }
  })
)

PostVisualBacktest.propTypes = propTypes

PostVisualBacktest.defaultProps = {
  history: {
    historyPrice: []
  }
}

export default enhance(PostVisualBacktest)
