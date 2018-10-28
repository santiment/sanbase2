import React from 'react'
import { graphql, compose } from 'react-apollo'
import { connect } from 'react-redux'
import {
  totalMarketcapGQL,
  constructTotalMarketcapGQL
} from './TotalMarketcapGQL'
import TotalMarketcapWidget from './TotalMarketcapWidget'
import moment from 'moment'

const composeHistoryPriceProps = slug => ({
  data: { historyPrice = [] },
  ownProps: { historyPrices: ownHistoryPrices = {} }
}) => ({
  historyPrices: {
    ...ownHistoryPrices,
    [slug]: historyPrice[slug]
  }
})

const getMarketcapQuery = (type, projects) => {
  const from = moment()
    .subtract(3, 'months')
    .utc()
    .format()

  if (type !== 'list') {
    return graphql(totalMarketcapGQL, {
      // props: composeHistoryPriceProps('TOTAL_MARKET'),
      props: ({ data: { historyPrice = [] } }) => ({
        historyPrices: {
          TOTAL_MARKET: historyPrice
        }
      }),
      options: () => ({
        variables: {
          from,
          slug: 'TOTAL_MARKET'
        }
      })
    })
  }

  const slugs = projects.slice(0, 10).map(({ slug }) => slug)

  const slugsQuery = graphql(constructTotalMarketcapGQL(slugs, from), {
    props: ({ data: historyPrice = {} }) => {
      return slugs.reduce(
        (acc, slug) => {
          acc.historyPrices[slug] = historyPrice['_' + slug.replace(/-/g, '')]
          return acc
        },
        {
          historyPrices: {}
        }
      )
    }
  })

  return slugsQuery
}

const GetTotalMarketcap = ({ type, from, projects, ...rest }) => {
  const resultQuery = getMarketcapQuery(type, projects)
  const HistoryQuery = resultQuery(TotalMarketcapWidget)
  return <HistoryQuery />
}

const mapStateToProps = state => ({
  projects: state.projects.items
})

export default connect(mapStateToProps)(GetTotalMarketcap)
