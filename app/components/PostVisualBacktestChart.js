import React from 'react'
import {
  ResponsiveContainer,
  LineChart,
  Line,
  XAxis,
  ReferenceLine
} from 'recharts'
import './PostVisualBacktestChart.css'

const Color = {
  POSITIVE: 'rgb(48, 157, 129)',
  NEGATIVE: 'rgb(200, 47, 63)'
}

const PostVisualBacktestChart = ({
  history: { historyPrice },
  postUpdatedAt,
  changePriceProp,
  change
}) => {
  const dataset = historyPrice.map(data => ({
    datetime: data.datetime,
    value: data[changePriceProp]
  }))
  return (
    <div className='PostVisualBacktestChart'>
      <ResponsiveContainer width='100%'>
        <LineChart
          data={dataset}
          margin={{ top: 5, right: 5, left: 0, bottom: 5 }}
        >
          <XAxis dataKey='datetime' hide />
          <ReferenceLine
            x={postUpdatedAt}
            stroke={change > 0 ? Color.POSITIVE : Color.NEGATIVE}
          />
          <Line
            dataKey='value'
            type='linear'
            dot={false}
            strokeWidth={2}
            stroke='#000000'
            isAnimationActive={false}
          />
        </LineChart>
      </ResponsiveContainer>
    </div>
  )
}

export default PostVisualBacktestChart
