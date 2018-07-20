import React from 'react'
import PropTypes from 'prop-types'
import { Message, Label } from 'semantic-ui-react'
import { graphql } from 'react-apollo'
import { compose, withProps } from 'recompose'
import { HistoryPriceGQL } from './../pages/Detailed/DetailedGQL'
import PercentChanges from './PercentChanges'

const getChanges = (start, last, prop = 'priceUsd') =>
  (last[`${prop}`] - start[`${prop}`]) / start[`${prop}`] * 100

const isTotalMarket = ticker => ticker === 'Crypto Market'

const propTypes = {
  ticker: PropTypes.string.isRequired,
  history: PropTypes.object
}

export const PostVisualBacktest = ({ ticker, change, changeProp }) => {
  if (!change) return null
  return (
    <Message>
      <Label horizontal>{ticker}</Label>
      {changeProp} changes after publication
      {change && <PercentChanges changes={change} />}
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
          from,
          ticker: isTotalMarket(ticker) ? 'TOTAL_MARKET' : ticker
        }
      }
    }
  }),
  withProps(({ ticker, history = {} }) => {
    const { historyPrice } = history
    if (!historyPrice || historyPrice.length === 0) return {}
    const start = historyPrice[0]
    const last = historyPrice[historyPrice.length - 1]
    if (!start || !last) return {}
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

PostVisualBacktest.defaultProps = {
  history: {
    historyPrice: []
  }
}

export default enhance(PostVisualBacktest)
