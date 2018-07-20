import React from 'react'
import PropTypes from 'prop-types'
import { Message } from 'semantic-ui-react'
import { graphql } from 'react-apollo'
import { compose, withProps } from 'recompose'
import { HistoryPriceGQL } from './../pages/Detailed/DetailedGQL'
import PercentChanges from './PercentChanges'

const getChanges = (start, last, prop = 'priceUsd') =>
  (last[`${prop}`] - start[`${prop}`]) / start[`${prop}`] * 100

const isTotalMarket = ticker => ticker === 'Crypto Market'

const propTypes = {
  ticker: PropTypes.string.isRequired,
  from: PropTypes.string.isRequired
}

const PostVisualBacktest = ({ ticker, change, changeProp }) => (
  <Message>
    {changeProp} changes after publication
    {change && <PercentChanges changes={change} />}
  </Message>
)

const enhance = compose(
  graphql(HistoryPriceGQL, {
    name: 'history',
    options: ({ ticker, from }) => {
      return {
        skip: !ticker || !from,
        errorPolicy: 'all',
        variables: {
          from,
          ticker: isTotalMarket(ticker) ? 'TOTAL_MARKET' : ticker
        }
      }
    }
  }),
  withProps(({ ticker, history: { historyPrice = [] } }) => {
    const start = historyPrice[0]
    const last = historyPrice[historyPrice.length - 1]
    if (!start || !last) return
    const changeProp = isTotalMarket(ticker) ? 'Total marketcap' : 'Prices'
    return {
      change: getChanges(
        start,
        last,
        isTotalMarket(ticker) ? 'marketcap' : 'priceUsd'
      ),
      changeProp
    }
  })
)

PostVisualBacktest.propTypes = propTypes

export default enhance(PostVisualBacktest)
