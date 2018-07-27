import React from 'react'
import annotation from 'chartjs-plugin-annotation'
import { Line } from 'react-chartjs-2'
import './PostVisualBacktestChart.css'

const chartOptions = {
  animation: false,
  legend: {
    display: false
  },
  tooltips: {
    // enabled: false
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
        id: 'x-axis-0',
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
        options={{
          ...chartOptions,
          annotation: {
            annotations: [
              {
                drawTime: 'afterDatasetsDraw',
                type: 'line',
                mode: 'vertical',
                scaleID: 'x-axis-0',
                value: postCreatedAt,
                borderColor: 'red',
                borderWidth: 1
              }
            ]
          }
        }}
        // width={200}
        data={dataset}
      />
    </div>
  )
}

export default PostVisualBacktestChart
