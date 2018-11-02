import React from 'react'
import { graphql } from 'react-apollo'
import { connect } from 'react-redux'
import { compose } from 'recompose'
import moment from 'moment'
import { PieChart, Pie, Tooltip, ResponsiveContainer } from 'recharts'
import Widget from '../Widget/Widget'
import { piechartWatchlistWidgetGQL } from './piechartWatchlistWidgetGQL'
import { capitalizeStr } from '../../utils/utils'
import { formatNumber } from '../../utils/formatting'

const composeChartData = (projectsGroupStats = []) => {
  if (projectsGroupStats.length === 0) {
    return projectsGroupStats
  }

  const projectsData = projectsGroupStats[0]
  return projectsData.marketcapPercent.map(({ slug, percent }) => ({
    slug: capitalizeStr(slug),
    marketcap: percent * projectsData.marketcap
  }))
}

const PiechartWatchlistWidget = ({
  locationType,
  data: { projectsGroupStats }
}) => {
  if (locationType !== 'list') return null

  return (
    <Widget className='PiechartWatchlistWidget'>
      <h2 className='Widget__title'>Watchlist Assets Marketcap Piechart</h2>
      <div className='Widget__content'>
        <ResponsiveContainer>
          <PieChart>
            <Pie
              isAnimationActive={false}
              data={composeChartData(projectsGroupStats)}
              // cx={100}
              // cy={100}
              dataKey='marketcap'
              nameKey='slug'
              outerRadius={70}
              fill='rgb(48, 157, 129)'
            />
            <Tooltip
              formatter={value =>
                formatNumber(value, {
                  currency: 'USD'
                })
              }
            />
          </PieChart>
        </ResponsiveContainer>
      </div>
    </Widget>
  )
}

const mapStateToProps = state => ({
  projects: state.projects.items
})

const enhance = compose(
  connect(mapStateToProps),
  graphql(piechartWatchlistWidgetGQL, {
    options: ({ projects }) => {
      return {
        variables: {
          from: moment()
            .subtract(3, 'months')
            .utc()
            .format(),
          to: moment()
            .utc()
            .format(),
          slugs: projects.map(project => project.slug)
        }
      }
    }
  })
)

export default enhance(PiechartWatchlistWidget)
