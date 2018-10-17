import React from 'react'
import moment from 'moment'
import { compose, branch, renderComponent } from 'recompose'
import {
  ResponsiveContainer,
  ComposedChart,
  Line,
  CartesianGrid,
  XAxis,
  YAxis,
  Tooltip
} from 'recharts'
import { formatterCurrency } from './../../utils/formatting'

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

const xAxisTickFormatter = timeStr => moment(timeStr).format('DD MMM YY')
const yAxisTickFormatter = selectedCurrency => price =>
  formatterCurrency(price, selectedCurrency)
const TooltipFormatter = date => moment(date).format('dddd, MMM DD YYYY')

const priceLine = ({ selectedCurrency }) => (
  <Line
    type='linear'
    yAxisId='axis-price'
    name={selectedCurrency}
    dot={false}
    strokeWidth={2}
    dataKey={selectedCurrency === 'USD' ? 'priceUsd' : 'priceBtc'}
    stroke={ASSET_PRICE_COLOR}
  />
)

const AssetsChartReChart = ({
  History,
  selectedCurrency,
  isDesktop = false
}) => (
  <div className='TrendsExploreChart'>
    <ResponsiveContainer width='100%' height={300}>
      <ComposedChart
        data={History.items}
        margin={{
          top: 5,
          right: 10,
          left: isDesktop ? 30 : 5,
          bottom: 5
        }}
      >
        <CartesianGrid strokeDasharray='3 3' />
        <XAxis
          dataKey='datetime'
          tickLine={false}
          tickMargin={5}
          minTickGap={100}
          tickFormatter={xAxisTickFormatter}
        />
        <YAxis
          yAxisId='axis-price'
          type='number'
          hide={!isDesktop}
          padding={{ left: 40, right: 20 }}
          tickFormatter={yAxisTickFormatter(selectedCurrency)}
          domain={['dataMin', 'dataMax']}
        />
        <Tooltip
          labelFormatter={TooltipFormatter}
          formatter={formatterCurrency}
        />
        {priceLine({ selectedCurrency })}
      </ComposedChart>
    </ResponsiveContainer>
  </div>
)

export default compose(
  displayLoadingState,
  displayEmptyState
)(AssetsChartReChart)
