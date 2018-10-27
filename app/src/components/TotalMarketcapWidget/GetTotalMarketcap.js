import React from 'react'
import { graphql } from 'react-apollo'
import { connect } from 'react-redux'
import { totalMarketcapGQL, projectsGroupStats } from './TotalMarketcapGQL'
import TotalMarketcapWidget from './TotalMarketcapWidget'
import moment from 'moment'

const getMarketcapQuery = (type, projects) => {
  if (type === 'all') {
    return graphql(totalMarketcapGQL, {
      options: () => ({
        variables: {
          from: moment()
            .subtract(3, 'months')
            .utc()
            .format()
        }
      })
    })
  }

  return graphql(projectsGroupStats, {
    options: () => ({
      variables: {
        from: moment()
          .subtract(3, 'months')
          .utc()
          .format(),
        to: moment()
          .utc()
          .format(),
        slugs: projects.map(({ slug }) => slug)
      }
    })
  })
  // TODO:  all other cases to fetch project slugs from redux store '/projects/items'
}

const GetTotalMarketcap = ({ type, from, projects, ...rest }) => {
  const resultQuery = getMarketcapQuery(type, projects)

  console.log(
    moment()
      .utc()
      .format()
  )
  // store.getState().projects.items.map(({slug}) => slug)

  const Test = resultQuery(TotalMarketcapWidget)
  // return <Test {...rest} />
  return <Test test={123} />
}

// graphql(totalMarketcapGQL)(
//   TotalMarketcapWidget
// )

// GetTotalMarketcap.defaultProps = {
//   from: moment().subtract(3, 'months').utc().format(),
//   to: moment().utc().format(),
//   slug: 'TOTAL_MARKET'
// }

const mapStateToProps = state => ({
  projects: state.projects.items
})

export default connect(mapStateToProps)(GetTotalMarketcap)
