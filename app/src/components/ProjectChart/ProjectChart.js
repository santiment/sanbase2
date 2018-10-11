import React from 'react'
import PropTypes from 'prop-types'
import moment from 'moment'
import { pure } from 'recompose'
import { Bar, Chart } from 'react-chartjs-2'
import 'react-dates/initialize'
import 'react-dates/lib/css/_datepicker.css'
import { formatNumber, formatBTC } from '../../utils/formatting'
import './ProjectChart.css'
import './react-dates-override.css'

const COLORS = {
  price: '#00a05a',
  volume: 'rgba(49, 107, 174, 0.4)',
  marketcap: 'rgb(200, 47, 63)',
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
    fill: false,
    borderColor: COLORS.price,
    borderWidth: 1,
    backgroundColor: 'rgba(239, 242, 236, 0.5)',
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
    backgroundColor: COLORS.marketcap,
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
    }, {
      id: 'y-axis-4',
      type: 'linear',
      scaleLabel: {
        display: true,
        labelString: 'Github Activity',
        fontColor: COLORS.githubActivity
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
        fontColor: COLORS.twitter
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
        fontColor: COLORS.burnRate
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
        fontColor: COLORS.transactionVolume
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
  isDesktop,
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
    <div className='project-chart-body'>
      {isLoading && <div className='project-chart__isLoading'> Loading... </div>}
      {!isLoading && isEmpty && <div className='project-chart__isEmpty'> We don't have any data </div>}
      <Bar
        data={chartData}
        options={chartOptions}
        height={isDesktop ? 100 : undefined}
        onElementsClick={elems => {
          !props.isDesktop && elems[0] && setSelected(elems[0]._index)
        }}
        style={{ transition: 'opacity 0.25s ease' }}
      />
    </div>
  )
}

ProjectChart.propTypes = {
  isLoading: PropTypes.bool.isRequired,
  isError: PropTypes.bool.isRequired,
  history: PropTypes.array.isRequired,
  isEmpty: PropTypes.bool,
  isToggledBTC: PropTypes.bool,
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

export default pure(ProjectChart)
