import React from 'react'
import TrendsChart from '../TrendsChart'

const chartOptions = {
  animation: false,
  legend: {
    display: false
  },
  scales: {
    yAxes: [
      {
        display: false
      }
    ],
    xAxes: [
      {
        display: false
      }
    ]
  },
  elements: {
    point: {
      hitRadius: 0,
      radius: 0
    }
  }
}

const TrendsExamplesItemChart = props => (
  <TrendsChart {...props} chartOptions={chartOptions} height={null} />
)

export default TrendsExamplesItemChart
