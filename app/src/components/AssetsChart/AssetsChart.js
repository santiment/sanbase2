import React from 'react'
import withSizes from 'react-sizes'
import Panel from './../Panel'
import AssetsChartContainer from './AssetsChartContainer'
import AssetsChartHeader from './AssetsChartHeader'
import AssetsChartFooter from './AssetsChartFooter'
import AssetsChartReChart from './AssetsChartReChart'
import { mapSizesToProps } from './../../utils/utils'
import styles from './AssetsChart.module.css'

const AssetsChart = ({ slug = 'santiment', isDesktop }) => (
  <Panel className={styles.AssetsChartPanel}>
    <div className={styles.AssetsChart}>
      <AssetsChartHeader />
      <AssetsChartContainer
        slug={slug}
        render={props => (
          <AssetsChartReChart isDesktop={isDesktop} {...props} />
        )}
      />
      <AssetsChartFooter />
    </div>
  </Panel>
)

export default withSizes(mapSizesToProps)(AssetsChart)
