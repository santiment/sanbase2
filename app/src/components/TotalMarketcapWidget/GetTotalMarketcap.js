import React from 'react'
import { graphql, compose } from 'react-apollo'
import { connect } from 'react-redux'
import { totalMarketcapGQL } from './TotalMarketcapGQL'
import TotalMarketcapWidget from './TotalMarketcapWidget'
import moment from 'moment'

const composeHistoryPriceProps = slug => ({
  data: { historyPrice = [] },
  ownProps: { historyPrices: ownHistoryPrices = {} }
}) => ({
  historyPrices: {
    ...ownHistoryPrices,
    [slug]: historyPrice
  }
})

const getMarketcapQuery = (type, projects) => {
  const from = moment()
    .subtract(3, 'months')
    .utc()
    .format()
  console.log('TCL: getMarketcapQuery -> from', from)

  if (type !== 'list') {
    return graphql(totalMarketcapGQL, {
      props: composeHistoryPriceProps('TOTAL_MARKET'),
      options: () => ({
        variables: {
          from,
          slug: 'TOTAL_MARKET'
        }
      })
    })
  }

  const slugsQuery = projects.slice(0, 10).map(({ slug }) =>
    graphql(totalMarketcapGQL, {
      props: composeHistoryPriceProps(slug),
      options: () => ({
        variables: {
          from,
          slug
        }
      })
    })
  )

  return compose(...slugsQuery)
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
