import React from 'react'
import moment from 'moment'
import { compose, branch, renderComponent } from 'recompose'
import {
  ResponsiveContainer,
  ComposedChart,
  BarChart,
  Bar,
  Line,
  Area,
  CartesianGrid,
  XAxis,
  YAxis
} from 'recharts'
import { formatterCurrency } from './../../utils/formatting'
import volumeChart from './VolumeChart'
import datetimeXAxis from './DatetimeXAxis'
import priceChart from './PriceChart'
import tooltip from './Tooltip'

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

const yAxisTickFormatter = selectedCurrency => price =>
  formatterCurrency(price, selectedCurrency)
const TooltipFormatter = date => moment(date).format('dddd, MMM DD YYYY')

const AssetsChartReChart = ({
  History,
  selectedCurrency,
  isDesktop = false,
  settings = {}
}) => (
  <div className='TrendsExploreChart'>
    <ResponsiveContainer width='100%' height={300}>
      <ComposedChart
        syncId={'assets-chart'}
        data={History.items}
        margin={{
          top: 5,
          right: 10,
          left: isDesktop ? 30 : 5,
          bottom: 0
        }}
      >
        <CartesianGrid strokeDasharray='9 9' />
        {datetimeXAxis({ hide: true })}
        <XAxis hide />
        <YAxis
          yAxisId='axis-price'
          type='number'
          hide={!isDesktop}
          padding={{ left: 40, right: 20 }}
          tickFormatter={yAxisTickFormatter(selectedCurrency)}
          domain={['dataMin', 'dataMax']}
        />
        {tooltip()}
        {priceChart({ selectedCurrency })}
      </ComposedChart>
    </ResponsiveContainer>
    {settings.isToggledVolume &&
      volumeChart({ selectedCurrency, isDesktop, data: History.items })}
  </div>
)

export default compose(
  displayLoadingState,
  displayEmptyState
)(AssetsChartReChart)
