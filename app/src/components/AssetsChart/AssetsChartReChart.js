import React from 'react'
import moment from 'moment'
import outliers from 'outliers'
import { compose, branch, withProps, renderComponent } from 'recompose'
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
import { mergeTimeseriesByKey } from './../../utils/utils'
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
  chartData,
  TokenAge,
  History,
  selectedCurrency,
  isDesktop = false,
  settings = {}
}) => (
  <div className='TrendsExploreChart'>
    <ResponsiveContainer width='100%' height={300}>
      <ComposedChart
        syncId={'assets-chart'}
        data={chartData}
        margin={{
          top: 5,
          right: 10,
          left: isDesktop ? 30 : 5,
          bottom: 0
        }}
      >
        <CartesianGrid strokeDasharray='9 9' />
        {datetimeXAxis({ hide: true })}
        {datetimeXAxis({ hide: true })}
        <YAxis
          yAxisId='axis-price'
          type='number'
          hide={!isDesktop}
          padding={{ left: 40, right: 20 }}
          tickFormatter={yAxisTickFormatter(selectedCurrency)}
          domain={['dataMin', 'dataMax']}
        />
        <YAxis
          yAxisId='axis-burnRate'
          hide
          dataKey={'burnRate'}
          domain={['dataMin', 'dataMax']}
        />
        {tooltip()}
        {priceChart({ selectedCurrency, data: chartData })}
        <Line
          xAxisId='axis-datetime'
          connectNulls={true}
          animationBegin={200}
          strokeDasharray='2 3 4'
          yAxisId='axis-burnRate'
          dot={true}
          stroke='rgba(252, 138, 23, 0.7)'
          dataKey={'burnRate'}
        />
        {
          // <Bar
          // xAxisId='axis-datetime'
          // yAxisId='axis-burnRate'
          /// /dot={false}
          // fill='rgba(252, 138, 23, 0.7)'
          /// /minPointSize={5}
          // barSize={10}
          /// /background={{ fill: '#eee' }}
          // dataKey={'burnRate'} />
        }
      </ComposedChart>
    </ResponsiveContainer>
    {settings.isToggledVolume &&
      volumeChart({ selectedCurrency, isDesktop, data: chartData })}
  </div>
)

export default compose(
  withProps(({ TokenAge, History, ...rest }) => {
    if (!TokenAge) {
      return { chartData: [] }
    }
    const tokenAge = TokenAge.items || []
    const normalizeTokenAge = tokenAge.filter((val, i, arr) => {
      const result = outliers('burnRate')(val, i, arr)
      console.log(result)
      return result
    })
    console.log(tokenAge, normalizeTokenAge)
    const history = History.items || []
    const chartData = mergeTimeseriesByKey({
      timeseries: [normalizeTokenAge, history],
      key: 'datetime'
    })
    return {
      chartData
    }
  }),
  displayLoadingState,
  displayEmptyState
)(AssetsChartReChart)
