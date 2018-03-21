import React from 'react'
import PanelBlock from './../../components/PanelBlock'
import moment from 'moment'
import { Bar } from 'react-chartjs-2'

const COLOR = '#009663'

const getChartDataFromHistory = (history = []) => {
  return {
    labels: history ? history.map(data => moment(data.datetime).utc()) : [],
    datasets: [{
      label: 'Spent ETH',
      fill: true,
      borderColor: COLOR,
      borderWidth: 1,
      backgroundColor: 'rgba(239, 242, 236, 0.5)',
      pointBorderWidth: 2,
      pointRadius: 1,
      strokeColor: COLOR,
      data: history ? history.map(data => data.ethSpent) : []
    }]
  }
}

const chartOptions = {
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
  legend: {
    display: false
  },
  scales: {
    yAxes: [{
      ticks: {
        display: false,
        beginAtZero: false
      },
      gridLines: {
        drawBorder: false,
        display: false
      }
    }],
    xAxes: [{
      gridLines: {
        drawBorder: false,
        display: false
      },
      ticks: {
        display: false,
        beginAtZero: true
      }
    }]
  }
}

const SpentOverTime = ({loading = true, project = {}}) => {
  const chartData = getChartDataFromHistory(project.ethSpentOverTime)
  return (
    <PanelBlock
      isLoading={loading}
      title='ETH Spent Over Time'>
      {!project.ethSpentOverTime && "We don't have any data now"}
      <div className='analytics-trend-chart'>
        <Bar
          height={80}
          data={chartData}
          options={chartOptions}
          style={{ transition: 'opacity 0.25s ease' }}
          redraw
        />
      </div>
    </PanelBlock>
  )
}

export default SpentOverTime
