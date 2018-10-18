import React from 'react'
import { ResponsiveContainer, YAxis, BarChart, Bar } from 'recharts'
import tooltip from './Tooltip'
import datetimeXAxis from './DatetimeXAxis'

const volumeChart = ({ data, isDesktop, selectedCurrency }) => (
  <ResponsiveContainer width='100%' height={150}>
    <BarChart
      syncId={'assets-chart'}
      margin={{
        top: 0,
        right: 10,
        left: isDesktop ? 30 : 5,
        bottom: 5
      }}
      data={data}
    >
      <YAxis yAxisId={'axis-volume'} domain={['dataMin', 'dataMax']} />
      {tooltip()}
      {datetimeXAxis()}
      <Bar
        fill='#a4acb7'
        xAxisId='axis-datetime'
        yAxisId='axis-volume'
        dataKey={selectedCurrency === 'USD' ? 'volume' : 'volumeBTC'}
      />
    </BarChart>
  </ResponsiveContainer>
)

export default volumeChart
