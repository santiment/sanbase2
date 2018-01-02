import React from 'react'
import PropTypes from 'prop-types'
import {
  compose,
  pure,
  withState,
  withHandlers,
  lifecycle
} from 'recompose'
import { Merge } from 'animate-components'
import { fadeIn, slideUp } from 'animate-keyframes'
import { Bar, Chart } from 'react-chartjs-2'
import { DateRangePicker } from 'react-dates'
import 'react-dates/initialize'
import 'react-dates/lib/css/_datepicker.css'
import moment from 'moment'
import { formatNumber, formatBTC } from '../../utils/formatting'
import './ProjectChart.css'
import './react-dates-override.css'

const COLORS = {
  price: '#00a05a',
  volume: 'rgba(49, 107, 174, 0.5)',
  marketcap: 'rgb(200, 47, 63)'
}

export const TimeFilterItem = ({disabled, interval, setFilter, value = '1d'}) => {
  let cls = interval === value ? 'activated' : ''
  if (disabled) {
    cls += ' disabled'
  }
  return (
    <div
      className={cls}
      onClick={() => !disabled && setFilter(value)}>{value}</div>
  )
}

export const TimeFilter = props => (
  <div className='time-filter'>
    <TimeFilterItem value={'1d'} {...props} />
    <TimeFilterItem value={'1w'} {...props} />
    <TimeFilterItem value={'2w'} {...props} />
    <TimeFilterItem value={'1m'} {...props} />
  </div>
)

export const CurrencyFilter = ({isToggledBTC, showBTC, showUSD}) => (
  <div className='currency-filter'>
    <div
      className={isToggledBTC ? 'activated' : ''}
      onClick={showBTC}>BTC</div>
    <div
      className={!isToggledBTC ? 'activated' : ''}
      onClick={showUSD}>USD</div>
  </div>
)

const MarketcapToggle = ({isToggledMarketCap, toggleMarketcap}) => (
  <div className='marketcap-toggle'>
    <div
      className={isToggledMarketCap ? 'activated' : ''}
      onClick={() => toggleMarketcap(!isToggledMarketCap)}>MarketCap</div>
  </div>
)

const ProjectChartHeader = ({
  startDate,
  endDate,
  focusedInput,
  onFocusChange,
  changeDates,
  isDesktop,
  selected,
  history,
  ...props
}) => {
  return (
    <div className='chart-header'>
      <div className='chart-datetime-settings'>
        <TimeFilter {...props} />
        <DateRangePicker
          small
          startDateId='startDate'
          endDateId='endDate'
          startDate={startDate}
          endDate={endDate}
          onDatesChange={({ startDate, endDate }) => changeDates(startDate, endDate)}
          focusedInput={focusedInput}
          onFocusChange={onFocusChange}
          displayFormat={() => moment.localeData().longDateFormat('L')}
          hideKeyboardShortcutsPanel
          isOutsideRange={day => {
            const today = moment().endOf('day')
            return day > today
          }}
        />
      </div>
      {!isDesktop && [
        <div className='selected-value'>{selected &&
          <Merge
            one={{ name: fadeIn, duration: '0.3s', timingFunction: 'ease-in' }}
            two={{ name: slideUp, duration: '0.5s', timingFunction: 'ease-out' }}
            as='div'
          >
            <span className='selected-value-datetime'>
              {moment(history[selected].datetime).utc().format('MMMM DD, YYYY')}
            </span>
          </Merge>}</div>,
        <div className='selected-value'>{selected &&
          <Merge
            one={{ name: fadeIn, duration: '0.3s', timingFunction: 'ease-in' }}
            two={{ name: slideUp, duration: '0.5s', timingFunction: 'ease-out' }}
            as='div'
          >
            <span className='selected-value-data'>Price:
              {formatNumber(history[selected].priceUsd, 'USD')}</span>
            <span className='selected-value-data'>Volume:
              {formatNumber(history[selected].volume, 'USD')}</span>
          </Merge>}</div> ]}
    </div>
  )
}

const getChartDataFromHistory = (history = [], isToggledBTC, isToggledMarketCap) => {
  const priceDataset = {
    label: 'Price',
    type: 'LineWithLine',
    fill: !isToggledMarketCap,
    borderColor: COLORS.price,
    borderWidth: 1,
    backgroundColor: 'rgba(239, 242, 236, 0.5)',
    pointBorderWidth: 2,
    yAxisID: 'y-axis-1',
    data: history ? history.map(data => {
      if (isToggledBTC) {
        const price = parseFloat(data.priceBtc)
        return formatBTC(price)
      }
      return data.priceUsd
    }) : []}
  const volumeDataset = {
    label: 'Volume',
    fill: false,
    type: 'bar',
    yAxisID: 'y-axis-2',
    borderColor: COLORS.volume,
    backgroundColor: COLORS.volume,
    borderWidth: 4,
    pointBorderWidth: 1,
    data: history ? history.map(data => {
      if (isToggledBTC) {
        return parseFloat(data.volumeBTC)
      }
      return parseFloat(data.volume)
    }) : []}
  const marketcapDataset = !isToggledMarketCap ? null : {
    label: 'Marketcap',
    type: 'line',
    fill: false,
    yAxisID: 'y-axis-3',
    borderColor: COLORS.marketcap,
    borderWidth: 1,
    pointBorderWidth: 2,
    data: history ? history.map(data => {
      if (isToggledBTC) {
        return parseFloat(data.marketcapBTC)
      }
      return parseFloat(data.marketcap)
    }) : []}
  return {
    labels: history ? history.map(data => moment(data.datetime).utc()) : [],
    datasets: [priceDataset, marketcapDataset, volumeDataset].reduce((acc, curr) => {
      if (curr) acc.push(curr)
      return acc
    }, [])
  }
}

const renderTicks = props => {
  return function (value, index, values) {
    if (!values[index]) { return }
    return props.isToggledBTC
      ? formatBTC(value)
      : formatNumber(value, 'USD')
  }
}

const makeOptionsFromProps = props => ({
  responsive: true,
  showTooltips: true,
  pointDot: false,
  scaleShowLabels: false,
  datasetFill: false,
  scaleFontSize: 0,
  animation: false,
  pointRadius: 0,
  hover: {
    mode: 'nearest',
    intersect: true
  },
  tooltips: {
    mode: 'index',
    intersect: false,
    titleMarginBottom: 8,
    titleFontSize: 14,
    titleFontColor: '#000',
    backgroundColor: 'rgba(255, 255, 255, 0.8)',
    cornerRadius: 3,
    borderColor: '#d3d3d3',
    borderWidth: 2,
    bodyFontSize: 14,
    bodySpacing: 4,
    bodyFontColor: '#000',
    displayColors: true,
    callbacks: {
      title: item => {
        return item[0].xLabel.format('dddd, MMM DD YYYY, HH:mm:ss UTC')
      },
      label: (tooltipItem, data) => {
        const label = data.datasets[tooltipItem.datasetIndex].label.toString()
        return `${label}: ${props.isToggledBTC
          ? formatBTC(tooltipItem.yLabel)
          : formatNumber(tooltipItem.yLabel, 'USD')}`
      }
    }
  },
  legend: {
    display: false
  },
  elements: {
    point: {
      hitRadius: 2,
      hoverRadius: 2,
      radius: 0
    }
  },
  scales: {
    yAxes: [{
      id: 'y-axis-1',
      type: 'linear',
      display: true,
      position: 'left',
      scaleLabel: {
        display: true,
        labelString: `Price ${props.isToggledBTC ? '(BTC)' : '(USD)'}`,
        fontColor: COLORS.price
      },
      ticks: {
        display: true,
        beginAtZero: true,
        callback: renderTicks(props)
      },
      gridLines: {
        drawBorder: true,
        display: true,
        color: '#f0f0f0'
      }
    }, {
      id: 'y-axis-2',
      type: 'linear',
      display: false,
      position: 'right',
      scaleLabel: {
        display: false,
        labelString: 'Volume',
        fontColor: COLORS.volume
      },
      ticks: {
        // 2.2 is not a magic constant. We need to make volume
        // chart is not very high. It should be 20-30% of the maximum
        // In the future we have to make glued separate chart with volume.
        max: Math.max(...props.history.map(data =>
          props.isToggledBTC ? data.volumeBTC : data.volume)) * 2.2
      },
      labels: {
        show: true
      }
    }, {
      id: 'y-axis-3',
      type: 'linear',
      scaleLabel: {
        display: true,
        labelString: `MarketCap ${props.isToggledBTC ? '(BTC)' : '(USD)'}`,
        fontColor: COLORS.marketcap
      },
      ticks: {
        display: true,
        callback: renderTicks(props)
      },
      gridLines: {
        display: false
      },
      display: props.isToggledMarketCap,
      position: 'right'
    }],
    xAxes: [{
      type: 'time',
      ticks: {
        autoSkipPadding: 1,
        callback: function (value, index, values) {
          if (!values[index]) { return }
          const time = moment.utc(values[index]['value'])
          if (props.interval === '1d') {
            return time.format('HH:mm')
          }
          return time.format('D MMM')
        }},
      gridLines: {
        drawBorder: true,
        display: true,
        color: '#f0f0f0'
      }
    }]
  }
})

export const ProjectChart = ({
  isError,
  isEmpty,
  isLoading,
  errorMessage,
  setSelected,
  ...props
}) => {
  if (isError) {
    return (
      <div>
        <h2>We can't get the data from our server now... ;(</h2>
        <p>{errorMessage}</p>
      </div>
    )
  }
  const chartData = getChartDataFromHistory(props.history, props.isToggledBTC, props.isToggledMarketCap)
  const chartOptions = makeOptionsFromProps(props)

  return (
    <div className='project-dp-chart'>
      <ProjectChartHeader {...props} />
      <div className='project-chart-body'>
        {isLoading && <div className='project-chart__isLoading'> Loading... </div>}
        {!isLoading && isEmpty && <div className='project-chart__isEmpty'> We don't have any data </div>}
        <Bar
          data={chartData}
          options={chartOptions}
          redraw
          height={100}
          onElementsClick={elems => {
            !props.isDesktop && elems[0] && setSelected(elems[0]._index)
          }}
          style={{ transition: 'opacity 0.25s ease' }}
        />
      </div>
      <div className='chart-footer'>
        <div className='chart-footer-filters'>
          <CurrencyFilter {...props} />
          <MarketcapToggle {...props} />
        </div>
        <div>
          <small className='trademark'>santiment.net</small>
        </div>
      </div>
    </div>
  )
}

const enhance = compose(
  withState('isToggledBTC', 'currencyToggle', false),
  withHandlers({
    showBTC: ({ currencyToggle }) => e => currencyToggle(true),
    showUSD: ({ currencyToggle }) => e => currencyToggle(false)
  }),
  withState('isToggledMarketCap', 'toggleMarketcap', false),
  lifecycle({
    componentWillMount () {
      Chart.defaults.LineWithLine = Chart.defaults.line
      Chart.controllers.LineWithLine = Chart.controllers.line.extend({
        draw: function (ease) {
          Chart.controllers.line.prototype.draw.call(this, ease)

          if (this.chart.tooltip._active && this.chart.tooltip._active.length) {
            const activePoint = this.chart.tooltip._active[0]
            const ctx = this.chart.ctx
            const x = activePoint.tooltipPosition().x
            const topY = this.chart.scales['y-axis-1'].top
            const bottomY = this.chart.scales['y-axis-1'].bottom

            ctx.save()
            ctx.beginPath()
            ctx.moveTo(x, topY)
            ctx.lineTo(x, bottomY)
            ctx.lineWidth = 1
            ctx.strokeStyle = '#adadad'
            ctx.stroke()
            ctx.restore()
          }
        }
      })
    }
  }),
  pure
)

ProjectChart.propTypes = {
  isLoading: PropTypes.bool.isRequired,
  isError: PropTypes.bool.isRequired,
  history: PropTypes.array.isRequired,
  isEmpty: PropTypes.bool,
  selected: PropTypes.number,
  isDesktop: PropTypes.bool.isRequired,
  changeDates: PropTypes.func,
  startDate: PropTypes.object,
  endDate: PropTypes.object,
  focusedInput: PropTypes.string,
  onFocusChange: PropTypes.func
}

ProjectChart.defaultProps = {
  isLoading: true,
  isEmpty: true,
  isError: false,
  history: [],
  selected: undefined,
  isDesktop: true,
  focusedInput: null
}

export default enhance(ProjectChart)
