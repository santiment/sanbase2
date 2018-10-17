import React from 'react'
import Panel from './../Panel'
import AssetsChartContainer from './AssetsChartContainer'
import AssetsChartHeader from './AssetsChartHeader'
import AssetsChartReChart from './AssetsChartReChart'
import styles from './AssetsChart.module.css'

const AssetsChart = ({ slug = 'santiment' }) => (
  <Panel className={styles.AssetsChartPanel}>
    <div className={styles.AssetsChart}>
      <AssetsChartHeader />
      <AssetsChartContainer
        slug={slug}
        render={({ Project, History }) => (
          <AssetsChartReChart History={History} />
        )}
      />
    </div>
  </Panel>
)

export default AssetsChart
