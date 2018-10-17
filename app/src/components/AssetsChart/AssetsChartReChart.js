import React from 'react'
import moment from 'moment'
import { compose, withProps, branch, renderComponent } from 'recompose'
import {
  ResponsiveContainer,
  ComposedChart,
  Legend,
  Line,
  CartesianGrid,
  XAxis,
  YAxis,
  Tooltip
} from 'recharts'
import { formatNumber } from './../../utils/formatting'

const ASSET_PRICE_COLOR = '#a4acb7'

const Loading = () => <h2 style={{ marginLeft: 30 }}>Loading...</h2>

const Empty = () => (
  <h2 style={{ marginLeft: 30 }}>
    We can't find any data{' '}
    <span aria-label='sadly' role='img'>
      😞
    </span>
  </h2>
)

const displayLoadingState = branch(
  props => props.History.isLoading,
  renderComponent(Loading)
)

const displayEmptyState = branch(
  props => props.History.isEmpty,
  renderComponent(Empty)
)

const AssetsChartReChart = ({ History }) => {
  return (
    <div className='TrendsExploreChart'>
      <ResponsiveContainer width='100%' height={300}>
        <ComposedChart
          data={History.items}
          syncId='trends'
          margin={{ top: 5, right: 5, left: 0, bottom: 5 }}
        >
          <XAxis
            dataKey='datetime'
            tickLine={false}
            tickMargin={5}
            minTickGap={100}
            tickFormatter={timeStr => moment(timeStr).format('DD MMM YY')}
          />
          <YAxis />
          <YAxis
            yAxisId='axis-price'
            hide
            tickFormatter={priceUsd =>
              formatNumber(priceUsd, { currency: 'USD' })
            }
            domain={['dataMin', 'dataMax']}
          />
          <CartesianGrid strokeDasharray='3 3' />
          <Tooltip
            labelFormatter={date => moment(date).format('dddd, MMM DD YYYY')}
            formatter={(value, name) => {
              if (name === `USD`) {
                return formatNumber(value, { currency: 'USD' })
              }
              return value
            }}
          />
          <Line
            type='linear'
            yAxisId='axis-price'
            name={'USD'}
            dot={false}
            strokeWidth={2}
            dataKey='priceUsd'
            stroke={ASSET_PRICE_COLOR}
          />
          <Legend />
        </ComposedChart>
      </ResponsiveContainer>
    </div>
  )
}

export default compose(
  displayLoadingState,
  displayEmptyState
)(AssetsChartReChart)
