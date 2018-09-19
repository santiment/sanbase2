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
  Tooltip,
  Pie,
  PieChart,
  Cell
} from 'recharts'
import { formatNumber } from './../../utils/formatting'
import { mergeTimeseriesByKey } from './../../utils/utils'

const chartsMeta = {
  telegram: {
    index: 0,
    color: 'rgb(0, 0, 255)'
  },
  reddit: {
    index: 1,
    color: 'rgb(255, 0, 0)'
  },
  professional_traders_chat: {
    index: 2,
    color: 'rgb(20, 200, 20)'
  }
}

const Loading = () => <h2 style={{ marginLeft: 30 }}>Loading...</h2>

const displayLoadingState = branch(
  props => props.isLoading,
  renderComponent(Loading)
)

const TrendsReChart = ({ chartsMeta = {}, pieData = [], merged }) => (
  <div className='TrendsExploreChart'>
    {Object.keys(chartsMeta).map(key => (
      <ResponsiveContainer key={key} width='100%' height={300}>
        <ComposedChart
          data={merged}
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
              if (name === 'BTC/USD') {
                return formatNumber(value, { currency: 'USD' })
              }
              return value
            }}
          />
          <Line
            type='linear'
            yAxisId='axis-price'
            name='BTC/USD'
            dot={false}
            strokeWidth={2}
            dataKey='priceUsd'
            stroke='gold'
          />
          <Line
            type='linear'
            dataKey={key}
            dot={false}
            strokeWidth={3}
            stroke={chartsMeta[key].color}
          />
          <Legend />
        </ComposedChart>
      </ResponsiveContainer>
    ))}
    <br />
    <ResponsiveContainer width='100%' height={220}>
      <PieChart>
        <Pie
          dataKey='value'
          label={({ name, value }) => `${name}: ${value}`}
          data={pieData}
          outerRadius={80}
          fill='#8884d8'
        >
          {pieData.map((entry, index) => (
            <Cell key={index} fill={chartsMeta[entry.name].color} />
          ))}
        </Pie>
      </PieChart>
    </ResponsiveContainer>
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

export default compose(
  withProps(({ data = {}, trends }) => {
    const { items = [], isLoading = true } = data
    const telegram = getTimeseries('telegram', trends)
    const reddit = getTimeseries('reddit', trends)
    const professional_traders_chat = getTimeseries(
      'professional_traders_chat',
      trends
    )
    if (!telegram[0] || trends.isLoading || isLoading) {
      return {
        isLoading: true
      }
    }
    const merged = mergeTimeseriesByKey({
      timeseries: [items, telegram, reddit, professional_traders_chat],
      key: 'datetime'
    })

    const pieData = merged
      .reduce(
        (acc, val) => {
          if (val.telegram) {
            acc[0] = {
              ...acc[0],
              value: acc[0].value + val.telegram
            }
          }
          if (val.reddit) {
            acc[1] = {
              ...acc[1],
              value: acc[1].value + val.reddit
            }
          }
          if (val.professional_traders_chat) {
            acc[2] = {
              ...acc[2],
              value: acc[2].value + val.professional_traders_chat
            }
          }
          return acc
        },
        [
          {
            name: 'telegram',
            value: 0
          },
          {
            name: 'reddit',
            value: 0
          },
          {
            name: 'professional_traders_chat',
            value: 0
          }
        ]
      )
      .filter(source => source.value > 0)

    return {
      pieData,
      isLoading: false,
      merged,
      chartsMeta
    }
  }),
  displayLoadingState
)(TrendsReChart)
