import React from 'react'
import moment from 'moment'
import { ResponsiveContainer, LineChart, Line, XAxis, Tooltip } from 'recharts'
import { sourcesMeta, getMentionsChartData } from '../trendsUtils'

const Loading = () => <h2 style={{ marginLeft: 30 }}>Loading...</h2>

const TrendsExamplesItemChart = ({
  sources: mentionsBySources,
  selectedSources,
  isLoading
}) => {
  const result = isLoading
    ? null
    : getMentionsChartData(mentionsBySources, selectedSources)

  return (
    <div className='TrendsExploreChart'>
      {isLoading ? (
        <Loading />
      ) : (
        <ResponsiveContainer width='100%' height={150}>
          <LineChart
            data={result}
            margin={{ top: 5, right: 5, left: 0, bottom: 5 }}
          >
            <XAxis dataKey='datetime' hide />
            <Tooltip
              labelFormatter={date => moment(date).format('dddd, MMM DD YYYY')}
            />

            {selectedSources.map(source => (
              <Line
                key={sourcesMeta[source].index}
                dataKey={sourcesMeta[source].index}
                type='linear'
                dot={false}
                strokeWidth={1}
                name={sourcesMeta[source].name}
                stroke={sourcesMeta[source].color}
              />
            ))}
          </LineChart>
        </ResponsiveContainer>
      )}
    </div>
  )
}

export default TrendsExamplesItemChart
