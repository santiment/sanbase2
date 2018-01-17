import React from 'react'
import PropTypes from 'prop-types'
import cx from 'classnames'
import moment from 'moment'
import {
  compose,
  pure,
  withState,
  withHandlers
} from 'recompose'
import { Popup, Icon } from 'semantic-ui-react'
import { Merge } from 'animate-components'
import { fadeIn, slideUp } from 'animate-keyframes'
import { Bar, Chart } from 'react-chartjs-2'
import { DateRangePicker } from 'react-dates'
import 'react-dates/initialize'
import 'react-dates/lib/css/_datepicker.css'
import { formatNumber, formatBTC } from '../../utils/formatting'
import './ProjectChart.css'
import './react-dates-override.css'

const COLORS = {
  price: 'rgb(52, 171, 107)',
  volume: 'rgba(38, 43, 51, 0.25)',
  marketcap: 'rgb(52, 118, 153)',
  githubActivity: 'rgba(96, 76, 141, 0.7)', // Ultra Violet color #604c8d'
  twitter: 'rgba(16, 195, 245, 0.7)', // Ultra Violet color #604c8d'
  burnRate: 'rgba(252, 138, 23, 0.7)',
  transactionVolume: 'rgba(39, 166, 153, 0.7)'
}

// Fix X mode in Chart.js lib. Monkey loves this.
const originalX = Chart.Interaction.modes.x
Chart.Interaction.modes.x = function (chart, e, options) {
  const activePoints = originalX.apply(this, arguments)
  return activePoints.reduce((acc, item) => {
    const i = acc.findIndex(x => x._datasetIndex === item._datasetIndex)
    if (i <= -1) {
      acc.push(item)
    }
    return acc
  }, [])
}

// Draw a vertical line in our Chart, when tooltip is activated.
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

export const ToggleBtn = ({
  loading,
  disabled,
  isToggled,
  toggle,
  children
}) => (
  <div className={cx({
    'toggleBtn': true,
    'activated': isToggled,
    'disabled': disabled || loading
  })}
    onClick={() => !disabled && !loading && toggle(!isToggled)}>
    {disabled
      ? <Popup
        trigger={<span>{children}</span>}
        content="Looks like we don't have any data"
        position='top center'
      />
    : children}
    {loading && '(loading...)'}
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
      <CurrencyFilter {...props} />
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

const getChartDataFromHistory = (
  history = [],
  twitter = [],
  github = [],
  burnRate = [],
  transactionVolume = [],
  isToggledBTC,
  isToggledMarketCap,
  isToggledGithubActivity,
  isToggledVolume,
  isToggledTwitter,
  isToggledBurnRate,
  isToggledTransactionVolume
) => {
  const labels = history ? history.map(data => moment(data.datetime).utc()) : []
  const priceDataset = {
    label: 'Price',
    type: 'LineWithLine',
    fill: true,
    borderColor: COLORS.price,
    borderWidth: 1,
    backgroundColor: 'rgba(52, 171, 107, 0.03)',
    hitRadius: 2,
    yAxisID: 'y-axis-1',
    data: history ? history.map(data => {
      if (isToggledBTC) {
        const price = parseFloat(data.priceBtc)
        return formatBTC(price)
      }
      return data.priceUsd
    }) : []}
  const volumeDataset = !isToggledVolume ? null : {
    label: 'Volume',
    fill: false,
    type: 'bar',
    yAxisID: 'y-axis-2',
    borderColor: COLORS.volume,
    backgroundColor: COLORS.volume,
    borderWidth: 4,
    pointBorderWidth: 2,
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
    backgroundColor: 'rgba(52, 118, 153, 0.03)',
    borderWidth: 1,
    pointBorderWidth: 2,
    data: history.map(data => {
      if (isToggledBTC) {
        return parseFloat(data.marketcapBTC)
      }
      return parseFloat(data.marketcap)
    })}
  const githubActivityDataset = !isToggledGithubActivity ? null : {
    label: 'Github Activity',
    type: 'line',
    fill: false,
    yAxisID: 'y-axis-4',
    borderColor: COLORS.githubActivity,
    backgroundColor: COLORS.githubActivity,
    borderWidth: 1,
    pointBorderWidth: 2,
    pointRadius: 2,
    data: github.map(data => {
      return {
        x: moment(data.datetime),
        y: data.activity
      }
    })}
  const twitterDataset = !isToggledTwitter ? null : {
    label: 'Twitter',
    type: 'line',
    fill: false,
    yAxisID: 'y-axis-5',
    borderColor: COLORS.twitter,
    backgroundColor: COLORS.twitter,
    borderWidth: 1,
    pointBorderWidth: 2,
    pointRadius: 2,
    data: twitter.map(data => {
      return {
        x: moment(data.datetime),
        y: data.followersCount
      }
    })}
  const burnrateDataset = !isToggledBurnRate ? null : {
    label: 'Burn Rate',
    type: 'line',
    fill: false,
    yAxisID: 'y-axis-6',
    borderColor: COLORS.burnRate,
    backgroundColor: COLORS.burnRate,
    borderWidth: 1,
    pointBorderWidth: 2,
    pointRadius: 2,
    data: burnRate.map(data => {
      return {
        x: moment(data.datetime),
        y: data.burnRate / 10e8
      }
    })}
  const transactionVolumeDataset = !isToggledTransactionVolume ? null : {
    label: 'Transaction Volume',
    type: 'line',
    fill: false,
    yAxisID: 'y-axis-7',
    borderColor: COLORS.transactionVolume,
    backgroundColor: COLORS.transactionVolume,
    borderWidth: 1,
    pointBorderWidth: 2,
    pointRadius: 2,
    data: transactionVolume.map(data => {
      return {
        x: moment(data.datetime),
        y: data.transactionVolume / 10e8
      }
    })}
  return {
    labels,
    datasets: [
      priceDataset,
      marketcapDataset,
      githubActivityDataset,
      volumeDataset,
      twitterDataset,
      burnrateDataset,
      transactionVolumeDataset
    ].reduce((acc, curr) => {
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
  pointHitDetectionRadius: 2,
  datasetFill: false,
  scaleFontSize: 0,
  animation: false,
  pointRadius: 0,
  hover: {
    mode: 'x',
    intersect: false
  },
  tooltips: {
    mode: 'x',
    intersect: false,
    titleMarginBottom: 16,
    titleFontSize: 14,
    titleFontColor: '#3d4450',
    backgroundColor: 'rgba(255, 255, 255, 0.8)',
    cornerRadius: 3,
    borderColor: 'rgba(38, 43, 51, 0.7)',
    borderWidth: 1,
    bodyFontSize: 14,
    bodySpacing: 8,
    bodyFontColor: '#3d4450',
    displayColors: true,
    callbacks: {
      title: item => {
        return item[0].xLabel.format('dddd, MMM DD YYYY, HH:mm:ss UTC')
      },
      label: (tooltipItem, data) => {
        const label = data.datasets[tooltipItem.datasetIndex].label.toString()
        if (label === 'Github Activity' ||
          label === 'Burn Rate'
        ) {
          return `${label}: ${tooltipItem.yLabel}`
        }
        if (label === 'Transaction Volume') {
          return `${label}: ${tooltipItem.yLabel / 10e8} tokens`
        }
        if (label === 'Twitter') {
          return `${label}: ${tooltipItem.yLabel} followers`
        }
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
        fontColor: '#3d4450'
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
        fontColor: '#3d4450'
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
        fontColor: '#3d4450'
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
    }, {
      id: 'y-axis-4',
      type: 'linear',
      scaleLabel: {
        display: true,
        labelString: 'Github Activity',
        fontColor: '#3d4450'
      },
      ticks: {
        display: true,
        // same hack as in volume.
        max: parseInt(
          Math.max(...props.github.history.items.map(data => data.activity)) * 2.2, 10)
      },
      gridLines: {
        display: false
      },
      display: props.isToggledGithubActivity &&
        props.github.history.items.length !== 0,
      position: 'right'
    }, {
      id: 'y-axis-5',
      type: 'linear',
      tooltips: {
        mode: 'index',
        intersect: false
      },
      scaleLabel: {
        display: true,
        labelString: 'Twitter',
        fontColor: '#3d4450'
      },
      ticks: {
        display: true
      },
      gridLines: {
        display: false
      },
      display: props.isToggledTwitter &&
        props.twitter.history.items.length !== 0,
      position: 'right'
    }, {
      id: 'y-axis-6',
      type: 'linear',
      tooltips: {
        mode: 'index',
        intersect: false
      },
      scaleLabel: {
        display: true,
        labelString: 'Burn Rate',
        fontColor: '#3d4450'
      },
      ticks: {
        display: true,
        callback: (value, index, values) => {
          if (!values[index]) { return }
          return value / 10e8
        }
      },
      gridLines: {
        display: false
      },
      display: props.isToggledBurnRate &&
        props.burnRate.items.length !== 0,
      position: 'right'
    }, {
      id: 'y-axis-7',
      type: 'linear',
      tooltips: {
        mode: 'index',
        intersect: false
      },
      scaleLabel: {
        display: true,
        labelString: 'Transaction Volume',
        fontColor: '#3d4450'
      },
      ticks: {
        display: true,
        callback: (value, index, values) => {
          if (!values[index]) { return }
          return value / 10e8
        }
      },
      gridLines: {
        display: false
      },
      display: props.isToggledTransactionVolume &&
        props.transactionVolume.items.length !== 0,
      position: 'right'
    }],
    xAxes: [{
      type: 'time',
      time: {
        min: props.history && props.history.length > 0
          ? moment(props.history[0].datetime)
          : moment()
      },
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
        <h2> No data was returned </h2>
        <p>{errorMessage}</p>
      </div>
    )
  }
  const chartData = getChartDataFromHistory(
    props.history,
    props.twitter.history.items,
    props.github.history.items,
    props.burnRate.items,
    props.transactionVolume.items,
    props.isToggledBTC,
    props.isToggledMarketCap,
    props.isToggledGithubActivity,
    props.isToggledVolume,
    props.isToggledTwitter,
    props.isToggledBurnRate,
    props.isToggledTransactionVolume)
  const chartOptions = makeOptionsFromProps(props)

  return (
    <div className='project-dp-chart'>
      <ProjectChartHeader {...props} />
      <div className='project-chart-body'>
        {isLoading && <div className='project-chart__isLoading'> Loading... </div>}
        {!isLoading && isEmpty && <div className='project-chart__isEmpty'> No data was returned </div>}
        <Bar
          data={chartData}
          options={chartOptions}
          height={100}
          onElementsClick={elems => {
            !props.isDesktop && elems[0] && setSelected(elems[0]._index)
          }}
          style={{ transition: 'opacity 0.25s ease' }}
        />
      </div>
      <div className='chart-footer'>
        <div className='chart-footer-filters'>

          <div class="filter-cat">
            <div class="filter-cat-title">Financial</div>
            <ToggleBtn
              isToggled={props.isToggledMarketCap}
              toggle={props.toggleMarketcap}>
              Marketcap
            </ToggleBtn>
            <ToggleBtn
              isToggled={props.isToggledVolume}
              toggle={props.toggleVolume}>
              Volume
            </ToggleBtn>
          </div>

          <div class="filter-cat">
            <div class="filter-cat-title">Development</div>
            <ToggleBtn
              loading={props.github.history.loading}
              disabled={props.github.history.items.length === 0}
              isToggled={props.isToggledGithubActivity &&
                props.github.history.items.length !== 0}
              toggle={props.toggleGithubActivity}>
              Github Activity
            </ToggleBtn>
          </div>

          <div class="filter-cat">
            <div class="filter-cat-title">Blockchain</div>
            <ToggleBtn
              loading={props.burnRate.loading}
              disabled={props.burnRate.items.length === 0}
              isToggled={props.isToggledBurnRate &&
                props.burnRate.items.length !== 0}
              toggle={props.toggleBurnRate}>
              Burn Rate&nbsp;
              <Popup
                trigger={<Icon name='info circle' />}
                content='Token Burn Rate shows the amount of movement
                of tokens between addresses. One use for this metric is
                to spot large amounts of tokens moving after sitting for long periods of time'
                position='top left'
              />
            </ToggleBtn>
            <ToggleBtn
              loading={props.transactionVolume.loading}
              disabled={props.transactionVolume.items.length === 0}
              isToggled={props.isToggledTransactionVolume &&
                props.transactionVolume.items.length !== 0}
              toggle={props.toggleTransactionVolume}>
              Transaction Volume&nbsp;
              <Popup
                trigger={<Icon name='info circle' />}
                content='Total amount of tokens that were transacted on the blockchain'
                position='top left'
              />
            </ToggleBtn>
          </div>

          <div class="filter-cat">
            <div class="filter-cat-title">Social</div>
            <ToggleBtn
              loading={props.twitter.history.loading}
              disabled={props.twitter.history.items.length === 0}
              isToggled={props.isToggledTwitter &&
              props.twitter.history.items.length !== 0}
              toggle={props.toggleTwitter}>
              Twitter
            </ToggleBtn>
          </div>

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
  withState('isToggledGithubActivity', 'toggleGithubActivity', false),
  withState('isToggledVolume', 'toggleVolume', true),
  withState('isToggledTwitter', 'toggleTwitter', false),
  withState('isToggledBurnRate', 'toggleBurnRate', false),
  withState('isToggledTransactionVolume', 'toggleTransactionVolume', false),
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
