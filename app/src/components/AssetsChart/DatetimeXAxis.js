import React from 'react'
import moment from 'moment'
import { XAxis } from 'recharts'

const xAxisTickFormatter = timeStr => moment(timeStr).format('DD MMM YY')

const datetimeXAxis = (props = { hide: false }) => (
  <XAxis
    xAxisId='axis-datetime'
    dataKey='datetime'
    allowDataOverflow
    // scale={'utcTime'}
    hide={props.hide}
    tickLine={false}
    tickMargin={5}
    minTickGap={100}
    tickFormatter={xAxisTickFormatter}
  />
)

export default datetimeXAxis
