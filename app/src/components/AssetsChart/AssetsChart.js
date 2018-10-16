import React from 'react'
import Panel from './../Panel'
import AssetsChartContainer from './AssetsChartContainer'
import AssetsChartHeader from './AssetsChartHeader'
import styles from './AssetsChart.module.css'

const AssetsChart = () => (
  <Panel className={styles.AssetsChartPanel}>
    <AssetsChartContainer
      render={({ isLoading, timeRange }) => (
        <div className={styles.AssetsChart}>
          <AssetsChartHeader />
          <div style={{ height: 350 }}>
            AssetsChartBody {isLoading && 'isLoading...'}
            {timeRange}
          </div>
          <div>AssetsChartFooter</div>
        </div>
      )}
    />
  </Panel>
)

export default AssetsChart
