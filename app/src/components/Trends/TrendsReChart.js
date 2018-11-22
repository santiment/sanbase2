import React from 'react'
import moment from 'moment'
import withSizes from 'react-sizes'
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
import { mergeTimeseriesByKey } from './../../utils/utils'
import { sourcesMeta as chartsMeta } from './trendsUtils'
import { mapSizesToProps } from '../../App'

const ASSET_PRICE_COLOR = '#A4ACB7'

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
  props => props.isLoading,
  renderComponent(Loading)
)

/*
  0(false): mobile
  1(true): desktop
  */
const chartMargins = [
  { left: -20, right: 30 },
  { top: 5, right: 36, left: 0, bottom: 5 }
]

const displayEmptyState = branch(props => props.isEmpty, renderComponent(Empty))

const TrendsReChart = ({
  chartSummaryData = [],
  chartData,
  asset,
  isDesktop
}) => (
  <div className='TrendsExploreChart'>
    {chartSummaryData.map((entity, key) => (
      <ResponsiveContainer
        key={key}
        width='100%'
        height={isDesktop ? 300 : 250}
      >
        <ComposedChart
          data={chartData}
          syncId='trends'
          margin={chartMargins[+isDesktop]}
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
              if (name === `${asset}/USD`) {
                return formatNumber(value, { currency: 'USD' })
              }
              return value
            }}
          />
          <Line
            type='linear'
            yAxisId='axis-price'
            name={asset + '/USD'}
            dot={false}
            strokeWidth={1.5}
            dataKey='priceUsd'
            stroke={ASSET_PRICE_COLOR}
          />
          <Line
            type='linear'
            dataKey={entity.index}
            dot={false}
            strokeWidth={entity.index === 'merged' ? 1.5 : 3}
            name={entity.name}
            stroke={entity.color}
          />
          <Legend />
        </ComposedChart>
      </ResponsiveContainer>
    ))}
  </div>
)

TrendsReChart.defaultProps = {
  data: {},
  isLoading: true
}

const getTimeseries = (sourceName, trends) =>
  ((trends.sources || {})[sourceName] || []).map(el => {
    return {
      datetime: el.datetime,
      [sourceName]: el.mentionsCount
    }
  })

const calcSumOfMentions = data =>
  data.reduce(
    (acc, val) => {
      if (val.telegram) {
        acc.telegram = {
          ...acc.telegram,
          value: val.telegram + acc.telegram.value
        }
      }
      if (val.reddit) {
        acc.reddit = {
          ...acc.reddit,
          value: acc.reddit.value + val.reddit
        }
      }
      if (val.professional_traders_chat) {
        acc.professional_traders_chat = {
          ...acc.professional_traders_chat,
          value:
            acc.professional_traders_chat.value + val.professional_traders_chat
        }
      }
      return acc
    },
    { ...chartsMeta }
  )

const cleanAllZeroSources = data => data.filter(source => source.value > 0)

const objToArr = data => {
  return Object.keys(data).map(key => data[key])
}

export default compose(
  withProps(({ data = {}, trends }) => {
    const { items = [], isLoading = true } = data
    const telegram = getTimeseries('telegram', trends)
    const reddit = getTimeseries('reddit', trends)
    const professional_traders_chat = getTimeseries(
      'professional_traders_chat',
      trends
    )

    if (trends.isLoading || isLoading) {
      return {
        isLoading: true
      }
    }

    const chartData = mergeTimeseriesByKey({
      timeseries: [items, telegram, reddit, professional_traders_chat],
      key: 'datetime'
    })

    if (
      telegram.length === 0 &&
      reddit.length === 0 &&
      professional_traders_chat.length === 0
    ) {
      return {
        isEmpty: true
      }
    }

    const chartSummaryData = compose(
      cleanAllZeroSources,
      objToArr,
      calcSumOfMentions
    )(chartData)

    return {
      chartData,
      chartSummaryData,
      isLoading: false
    }
  }),
  withSizes(mapSizesToProps),
  displayLoadingState,
  displayEmptyState
)(TrendsReChart)
