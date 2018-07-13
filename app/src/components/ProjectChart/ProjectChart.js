import React, { Component } from 'react'
import PropTypes from 'prop-types'
import moment from 'moment'
import { Chart, Bar } from 'react-chartjs-2'
import 'react-dates/initialize'
import 'react-dates/lib/css/_datepicker.css'
import 'chartjs-plugin-datalabels'
import annotation from 'chartjs-plugin-annotation'
import { formatNumber, formatBTC, millify } from './../../utils/formatting'
import { findIndexByDatetime } from './../../utils/utils'
import './ProjectChart.css'
import './react-dates-override.css'

const COLORS_DAY = {
  price: 'rgb(52, 171, 107)',
  volume: 'rgba(38, 43, 51, 0.25)',
  marketcap: 'rgb(52, 118, 153)',
  githubActivity: 'rgba(96, 76, 141, 0.7)', // Ultra Violet color #604c8d'
  twitter: 'rgba(16, 195, 245, 0.7)',
  burnRate: 'rgba(252, 138, 23, 0.7)',
  transactionVolume: 'rgba(39, 166, 153, 0.7)',
  ethSpentOverTime: '#c82f3f',
  ethPrice: '#3c3c3d',
  sentiment: '#e23ab4',
  grid: '#f0f0f0',
  TOOLTIP_X: {
    titleFontColor: '#3d4450',
    backgroundColor: 'rgba(255, 255, 255, 0.8)',
    borderColor: 'rgba(38, 43, 51, 0.7)',
    bodyFontColor: '#3d4450'
  }
}

const COLORS_NIGHT = {
  ...COLORS_DAY,
  volume: '#3e3e3e',
  grid: '#4a4a4a',
  TOOLTIP_X: {
    titleFontColor: '#a0a0a0',
    backgroundColor: 'rgba(35, 37, 42, 0.87)',
    borderColor: '#4a4a4a',
    bodyFontColor: '#a0a0a0'
  }
}

const makeChartDataFromHistory = ({
  history = [],
  isToggledBTC,
  isToggledMarketCap,
  isToggledGithubActivity,
  isToggledVolume,
  isToggledTwitter,
  isToggledBurnRate,
  isToggledTransactionVolume,
  isToggledEthSpentOverTime,
  isToggledEthPrice = false,
  isToggledDailyActiveAddresses = false,
  isToggledEmojisSentiment,
  ...props
}, COLORS) => {
  const github = props.github.history.items || []
  const burnRate = props.burnRate.items || []
  const transactionVolume = props.transactionVolume.items || []
  const dailyActiveAddresses = props.dailyActiveAddresses.items || []
  const labels = history ? history.map(data => moment(data.datetime).utc()) : []
  const eventIndex = findIndexByDatetime(labels, '2018-01-13T18:00:00Z')
  const priceDataset = {
    label: 'Price',
    type: 'LineWithLine',
    fill: true,
    borderColor: COLORS.price,
    borderWidth: 1,
    backgroundColor: 'rgba(52, 171, 107, 0.03)',
    hitRadius: 2,
    yAxisID: 'y-axis-1',
    datalabels: {
      display: context => {
        return props.ticker === 'SAN' && context.dataIndex === eventIndex
      }
    },

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
    datalabels: {
      display: false
    },
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
    datalabels: {
      display: false
    },
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
    datalabels: {
      display: false
    },
    borderColor: COLORS.githubActivity,
    backgroundColor: COLORS.githubActivity,
    borderWidth: 1,
    pointBorderWidth: 2,
    pointRadius: 2,
    data: github.map(data => {
      return {
        x: data.datetime,
        y: data.activity
      }
    })}
  const twitterDataset = !isToggledTwitter ? null : {
    label: 'Twitter',
    type: 'line',
    fill: false,
    yAxisID: 'y-axis-twitter',
    datalabels: {
      display: false
    },
    borderColor: COLORS.twitter,
    backgroundColor: COLORS.twitter,
    borderWidth: 1,
    pointBorderWidth: 2,
    pointRadius: 2,
    data: props.twitterHistory.items.map(data => {
      return {
        x: data.datetime,
        y: data.followersCount
      }
    })}

  const burnrateDataset = !isToggledBurnRate ? null : {
    label: 'Burn Rate',
    type: 'bar',
    fill: false,
    yAxisID: 'y-axis-6',
    datalabels: {
      display: false
    },
    borderColor: COLORS.burnRate,
    backgroundColor: COLORS.burnRate,
    borderWidth: 1,
    pointBorderWidth: 2,
    pointRadius: 2,
    data: burnRate.map(data => {
      return {
        x: data.datetime,
        y: data.burnRate
      }
    })}
  const transactionVolumeDataset = !isToggledTransactionVolume ? null : {
    label: 'Transaction Volume',
    type: 'bar',
    fill: false,
    yAxisID: 'y-axis-7',
    datalabels: {
      display: false
    },
    borderColor: COLORS.transactionVolume,
    backgroundColor: COLORS.transactionVolume,
    borderWidth: 1,
    pointBorderWidth: 2,
    pointRadius: 2,
    data: transactionVolume.map(data => {
      return {
        x: data.datetime,
        y: data.transactionVolume
      }
    })}

  const ethSpentOverTimeByErc20ProjectsDataset = !isToggledEthSpentOverTime ? null : {
    label: 'ETH Spent Over time',
    type: 'bar',
    fill: false,
    yAxisID: 'y-axis-8',
    datalabels: {
      display: false
    },
    borderColor: COLORS.ethSpentOverTime,
    backgroundColor: COLORS.ethSpentOverTime,
    borderWidth: 1,
    pointBorderWidth: 2,
    pointRadius: 2,
    data: props.ethSpentOverTimeByErc20Projects.items.map(data => {
      return {
        x: data.datetime,
        y: data.ethSpent
      }
    })}
  const ethPriceDataset = !isToggledEthPrice ? null : {
    label: 'ETH Price',
    type: 'line',
    fill: false,
    yAxisID: 'y-axis-9',
    datalabels: {
      display: false
    },
    borderColor: COLORS.ethPrice,
    backgroundColor: COLORS.ethPrice,
    borderWidth: 1,
    data: props.ethPrice.history.items ? props.ethPrice.history.items.map(data => {
      if (isToggledBTC) {
        return {
          x: data.datetime,
          y: parseFloat(data.priceBtc)
        }
      }
      return {
        x: data.datetime,
        y: parseFloat(data.priceUsd)
      }
    }) : []}

  const sentimentEmojisDataset = !isToggledEmojisSentiment ? null : {
    label: 'Sentiment',
    type: 'line',
    fill: false,
    yAxisID: 'y-axis-sentiment',
    datalabels: {
      display: false
    },
    borderColor: COLORS.sentiment,
    backgroundColor: COLORS.sentiment,
    borderWidth: 1,
    pointBorderWidth: 2,
    pointRadius: 2,
    data: props.emojisSentiment.items.map(data => {
      return {
        x: data.datetime,
        y: data.sentiment
      }
    })}

  const dailyActiveAddressesDataset = !isToggledDailyActiveAddresses ? null : {
    label: 'Daily Active Addresses',
    type: 'bar',
    fill: false,
    yAxisID: 'y-axis-11',
    datalabels: {
      display: false
    },
    borderColor: COLORS.twitter,
    backgroundColor: COLORS.twitter,
    borderWidth: 1,
    pointBorderWidth: 2,
    pointRadius: 2,
    data: dailyActiveAddresses.map(data => {
      return {
        x: data.datetime,
        y: data.activeAddresses
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
      transactionVolumeDataset,
      ethSpentOverTimeByErc20ProjectsDataset,
      ethPriceDataset,
      dailyActiveAddressesDataset,
      sentimentEmojisDataset
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
      : formatNumber(value, { currency: 'USD' })
  }
}

const getICOPriceAnnotation = props => {
  if (props.isToggledBTC) { return undefined }
  const icoPrice = props.project.icoPrice || undefined
  const icoPriceUSD = icoPrice
    ? formatNumber(icoPrice, { currency: 'USD' })
    : undefined
  return icoPrice
    ? {
      events: ['hover'],
      annotations: [
        {
          drawTime: 'afterDatasetsDraw',
          id: 'hline',
          type: 'line',
          mode: 'horizontal',
          scaleID: 'y-axis-1',
          value: icoPrice,
          borderColor: 'black',
          borderWidth: 1,
          borderDash: [2, 2],
          label: {
            backgroundColor: 'rgba(255, 255, 255, 0.2)',
            fontColor: 'black',
            content: `ICO Price ${icoPriceUSD}`,
            enabled: true,
            position: 'left',
            yAdjust: -10
          },
          onHover: function (e) {
            // The annotation is is bound to the `this` variable
            console.log('Annotation', e.type, this)
          }
        }
      ]
    }
    : undefined
}

const makeOptionsFromProps = (props, COLORS) => {
  return {
    annotation: props.isToggledICOPrice
      ? getICOPriceAnnotation(props)
      : undefined,
    responsive: true,
    showTooltips: true,
    pointDot: false,
    scaleShowLabels: false,
    pointHitDetectionRadius: 2,
    datasetFill: false,
    scaleFontSize: 0,
    animation: false,
    pointRadius: 0,
    maintainAspectRatio: true,
    plugins: {
      datalabels: {
        display: false,
        anchor: 'end',
        align: 'top',
        backgroundColor: context => {
          return 'rgba(96, 76, 141, 0)'
        },
        borderRadius: 1,
        borderColor: 'black',
        borderWidth: 1,
        offset: 0,
        color: 'black',
        font: {
          size: 12
        },
        formatter: () => {
          return 'Tokens distributed to advisors'
        }
      }
    },
    hover: {
      mode: 'x',
      intersect: false
    },
    tooltips: {
      mode: 'x',
      intersect: false,
      titleMarginBottom: 16,
      titleFontSize: 14,
      titleFontColor: COLORS.TOOLTIP_X.titleFontColor,
      backgroundColor: COLORS.TOOLTIP_X.backgroundColor,
      cornerRadius: 3,
      borderColor: COLORS.TOOLTIP_X.borderColor,
      borderWidth: 1,
      bodyFontSize: 14,
      bodySpacing: 8,
      bodyFontColor: COLORS.TOOLTIP_X.bodyFontColor,
      displayColors: true,
      callbacks: {
        title: item => {
          return moment(item[0].xLabel).format('dddd, MMM DD YYYY, HH:mm:ss UTC')
        },
        label: (tooltipItem, data) => {
          const label = data.datasets[tooltipItem.datasetIndex].label.toString()
          if (label === 'Github Activity') {
            return `${label}: ${millify(tooltipItem.yLabel)}`
          }
          if (label === 'Burn Rate') {
            return `${label}: ${millify(tooltipItem.yLabel)} (tokens × blocks)`
          }
          if (label === 'Transaction Volume') {
            return `${label}: ${millify(tooltipItem.yLabel)} tokens`
          }
          if (label === 'Twitter') {
            return `${label}: ${millify(tooltipItem.yLabel)} followers`
          }
          if (label === 'Marketcap') {
            return `${label}: ${millify(tooltipItem.yLabel)}`
          }
          if (label === 'ETH Spent Over time') {
            return `${label}: ${millify(tooltipItem.yLabel)}`
          }
          if (label === 'Sentiment') {
            return `${label}: ${tooltipItem.yLabel}`
          }
          if (label === 'Daily Active Addresses') {
            return `${label}: ${millify(tooltipItem.yLabel)}`
          }
          return `${label}: ${props.isToggledBTC
            ? formatBTC(tooltipItem.yLabel)
            : formatNumber(tooltipItem.yLabel, { currency: 'USD' })}`
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
          display: false,
          labelString: `Price ${props.isToggledBTC ? '(BTC)' : '(USD)'}`,
          fontColor: '#3d4450'
        },
        ticks: {
          display: !props.isLoading,
          beginAtZero: false,
          autoSkip: false,
          callback: renderTicks(props),
          maxRotation: props.isToggledBTC ? 35 : 0,
          minRotation: props.isToggledBTC ? 35 : 0
        },
        gridLines: {
          drawBorder: true,
          display: true,
          color: COLORS.grid
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
          callback: (value, index, values) => {
            if (!values[index]) { return }
            return millify(value)
          }
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
        afterTickToLabelConversion: scaleInstance => {
          scaleInstance.ticks[0] = null
          scaleInstance.ticksAsNumbers[0] = null
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
        id: 'y-axis-twitter',
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
          props.historyTwitter &&
          props.historyTwitter.items &&
          props.historyTwitter.items.length !== 0,
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
        afterTickToLabelConversion: scaleInstance => {
          scaleInstance.ticks[0] = null
          scaleInstance.ticksAsNumbers[0] = null
        },
        ticks: {
          display: true,
          // same hack as in volume.
          max: parseInt(
            Math.max(...props.burnRate.items.map(data => data.burnRate)) * 2.2, 10),
          callback: (value, index, values) => {
            if (!values[index]) { return }
            return millify(value)
          },
          maxRotation: 20
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
        afterTickToLabelConversion: scaleInstance => {
          scaleInstance.ticks[0] = null
          scaleInstance.ticksAsNumbers[0] = null
        },
        ticks: {
          display: true,
          max: parseInt(
            Math.max(...props.transactionVolume.items.map(data => data.transactionVolume)) * 2.2, 10),
          callback: (value, index, values) => {
            if (!values[index]) { return }
            return millify(value)
          }
        },
        gridLines: {
          display: false
        },
        display: props.isToggledTransactionVolume &&
          props.transactionVolume.items.length !== 0,
        position: 'right'
      }, {
        id: 'y-axis-8',
        tooltips: {
          mode: 'index',
          intersect: false
        },
        scaleLabel: {
          display: true,
          labelString: 'ETH Spent Over Time',
          fontColor: '#3d4450'
        },
        afterTickToLabelConversion: scaleInstance => {
          scaleInstance.ticks[0] = null
          scaleInstance.ticksAsNumbers[0] = null
        },
        ticks: {
          display: true,
          ticks: {
            max: parseInt(Math.max(...props.ethSpentOverTime.items.filter(data => {
              return moment(data.datetime).isAfter(props.from) &&
                moment(data.datetime).isBefore(props.to)
            }).map(data => data.ethSpent)), 10)
          },
          callback: (value, index, values) => {
            if (!values[index]) { return }
            return millify(value)
          }
        },
        gridLines: {
          display: false
        },
        display: props.isToggledEthSpentOverTime &&
          props.ethSpentOverTimeByErc20Projects.items.length !== 0,
        position: 'right'
      }, {
        id: 'y-axis-9',
        position: 'right',
        scaleLabel: {
          display: true,
          labelString: `ETH Price ${props.isToggledBTC ? '(BTC)' : '(USD)'}`,
          fontColor: '#3d4450'
        },
        ticks: {
          display: false,
          beginAtZero: false,
          callback: renderTicks(props)
        },
        gridLines: {
          drawBorder: false,
          display: false
        },
        display: props.isToggledEthPrice
      }, {
        id: 'y-axis-sentiment',
        position: 'right',
        scaleLabel: {
          display: false,
          labelString: `Sentiment`,
          fontColor: '#3d4450'
        },
        ticks: {
          display: false,
          beginAtZero: false,
          callback: renderTicks(props)
        },
        gridLines: {
          drawBorder: false,
          display: false
        },
        display: props.isToggledEmojisSentiment
      }, {
        id: 'y-axis-11',
        position: 'right',
        scaleLabel: {
          display: false,
          labelString: `Daily Active Addresses`,
          fontColor: '#3d4450'
        },
        ticks: {
          display: false,
          beginAtZero: false,
          callback: renderTicks(props)
        },
        gridLines: {
          drawBorder: false,
          display: false
        },
        display: props.isToggledDailyActiveAddresses
      }],
      xAxes: [{
        type: 'time',
        maxBarThickness: 10,
        categoryPercentage: 0.6,
        barPercentage: 0.6,
        time: {
          min: props.history && props.history.length > 0
            ? moment(props.history[0].datetime)
            : moment()
        },
        ticks: {
          autoSkipPadding: 1,
          display: !props.isLoading,
          callback: function (value, index, values) {
            if (!values[index]) { return }
            const time = moment.utc(values[index]['value'])
            const {from, to} = props.timeFilter
            const diff = moment(to).diff(from, 'days')
            if (diff <= 1) {
              return time.format('HH:mm')
            }
            if (diff > 1 && diff < 95) {
              return time.format('D MMM')
            }
            return time.format('MMMM Y')
          }
        },
        gridLines: {
          drawBorder: true,
          offsetGridLines: true,
          display: true,
          color: COLORS.grid
        }
      }]
    }
  }
}

class ProjectChart extends Component {
  componentWillMount () {
    Chart.plugins.register(annotation)
  }

  render () {
    const {
      isNightModeEnabled,
      isDesktop,
      isError,
      isEmpty,
      errorMessage,
      setSelected,
      ...props
    } = this.props
    const isLoading = props.isLoading
    if (isError) {
      return (
        <div>
          <h2> No data was returned </h2>
          <p>{errorMessage}</p>
        </div>
      )
    }
    const colorMode = isNightModeEnabled ? COLORS_NIGHT : COLORS_DAY
    const chartData = makeChartDataFromHistory(props, colorMode)
    const chartOptions = makeOptionsFromProps(props, colorMode)

    return (
      <div className='project-chart-body'>
        {isLoading && <div className='project-chart__isLoading'> Loading... </div>}
        {!isLoading && isEmpty && <div className='project-chart__isEmpty'> We don't have any data </div>}
        <Bar
          data={chartData}
          options={chartOptions}
          height={isDesktop ? 80 : undefined}
          redraw
          onElementsClick={elems => {
            !props.isDesktop && elems[0] && setSelected(elems[0]._index)
          }}
          style={{ transition: 'opacity 0.25s ease' }}
        />
      </div>
    )
  }
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

export default ProjectChart
