import React from 'react'
import { Line } from 'react-chartjs-2'
import './PostVisualBacktestChart.css'

const chartOptions = {
  animation: false,
  legend: {
    display: false
  },
  tooltips: {
    enabled: false
  },
  scales: {
    yAxes: [
      {
        ticks: {
          display: false
        },
        gridLines: {
          display: false,
          color: '#4a4a4a'
        }
      }
    ],
    xAxes: [
      {
        ticks: {
          display: false
        },
        gridLines: {
          display: false,
          color: '#4a4a4a'
        }
      }
    ]
  }
}

const datasetOptions = {
  borderColor: 'rgba(255, 193, 7, 1)',
  borderWidth: 1,
  pointRadius: 0,
  fill: false
}

const PostVisualBacktestChart = ({
  history: { historyPrice },
  postCreatedAt,
  changePriceProp
}) => {
  // console.log(postCreatedAt)
  const dataset = {
    labels: historyPrice.map(data => data.datetime),
    datasets: [
      {
        data: historyPrice.map(data => data[changePriceProp]),
        ...datasetOptions
      }
    ]
  }

  return (
    <div className='PostVisualBacktestChart'>
      <Line
        className='PostVisualBacktestChart'
        options={chartOptions}
        // width={200}
        data={dataset}
      />
    </div>
  )
}

export default PostVisualBacktestChart
