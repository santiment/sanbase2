import React from 'react'
// import TrendsChart from '../TrendsChart'
// import TrendsReChart from '../TrendsReChart'
import moment from 'moment'
import { mergeDataSourcesForChart } from '../trendsUtils'
import { ResponsiveContainer, LineChart, Line, XAxis, Tooltip } from 'recharts'

const chartsMeta = {
  merged: {
    index: 'merged',
    name: 'Merged',
    color: 'rgb(255, 193, 7)',
    value: 0
  },
  telegram: {
    index: 'telegram',
    name: 'Telegram',
    color: '#2d79d0',
    value: 0
  },
  reddit: {
    index: 'reddit',
    name: 'Reddit',
    color: '#c82f3f',
    value: 0
  },
  professional_traders_chat: {
    index: 'professional_traders_chat',
    name: 'Professional Traders Chat',
    color: '#26a987',
    value: 0
  }
}

const Loading = () => <h2 style={{ marginLeft: 30 }}>Loading...</h2>

const Empty = () => (
  <h2 style={{ marginLeft: 30 }}>
    We can't find any data{' '}
    <span aria-label='sadly' role='img'>
      😞
    </span>
  </h2>
)

/*
mentionsBySources : {
  telegram : [
    {
      mentionsCount: number,
      datetime: string
    },
    {

    }
  ],
  reddit : [
    {
      ....
    }
  ]

}
*/

const getMergedMentionsDataset = mentionsBySources =>
  Object.keys(mentionsBySources).reduce((acc, source) => {
    for (const { datetime, mentionsCount } of mentionsBySources[source]) {
      if (acc[datetime] !== undefined) {
        acc[datetime].merged += mentionsCount
      } else {
        acc[datetime] = {
          datetime,
          merged: mentionsCount
        }
      }
    }
    return acc
  }, {})

const getComposedMentionsDataset = (mentionsBySources, selectedSources) => {
  return selectedSources.reduce((acc, source) => {
    for (const { datetime, mentionsCount } of mentionsBySources[source]) {
      if (acc[datetime] !== undefined) {
        acc[datetime][source] = mentionsCount
      } else {
        acc[datetime] = {
          datetime,
          [source]: mentionsCount
        }
      }
    }
    return acc
  }, {})
}

const TrendsReChart = ({
  selectedSources,
  mentionsBySources,
  chartData,
  asset
}) => {
  const result = Object.values(
    selectedSources.includes('merged')
      ? getMergedMentionsDataset(mentionsBySources)
      : getComposedMentionsDataset(mentionsBySources, selectedSources)
  ).sort((a, b) => (moment(a.datetime).isAfter(b.datetime) ? 1 : -1))

  return (
    <div className='TrendsExploreChart'>
      <ResponsiveContainer width='100%' height={150}>
        <LineChart
          data={result}
          margin={{ top: 5, right: 5, left: 0, bottom: 5 }}
        >
          <XAxis dataKey='datetime' hide />
          <Tooltip
            labelFormatter={date => moment(date).format('dddd, MMM DD YYYY')}
          />

          {selectedSources.map(source => {
            const sourceMeta = chartsMeta[source] || {}
            return (
              <Line
                key={sourceMeta.index}
                dataKey={sourceMeta.index}
                type='linear'
                dot={false}
                strokeWidth={3}
                name={sourceMeta.name}
                stroke={sourceMeta.color}
              />
            )
          })}
        </LineChart>
      </ResponsiveContainer>
    </div>
  )
}

const TrendsExamplesItemChart = ({
  topic,
  sources,
  selectedSources,
  isLoading,
  isError
}) => (
  <TrendsReChart
    selectedSources={selectedSources}
    asset={topic}
    mentionsBySources={sources}
  />
)

TrendsReChart.defaultProps = {
  data: {},
  isLoading: true
}

export default TrendsExamplesItemChart
