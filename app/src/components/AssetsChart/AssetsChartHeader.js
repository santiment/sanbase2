import React from 'react'
import { connect } from 'react-redux'
import Selector from './../Selector/Selector'
import { selectTimeRange, selectCurrency } from './AssetsChart.reducers.js'
import styles from './AssetsChartHeader.module.css'

const AssetsChartHeader = ({
  handleSelectTimeRange,
  timeRange,
  handleSelectCurrency,
  currency
}) => (
  <div className={styles.AssetsChartHeader}>
    <Selector
      options={['1d', '1w', '2w', '1m', '3m', 'all']}
      onSelectOption={handleSelectTimeRange}
      defaultSelected={timeRange}
    />
    <div className={styles.Right}>
      <Selector
        options={['BTC', 'USD']}
        onSelectOption={handleSelectCurrency}
        defaultSelected={currency}
      />
      <span>Share Button</span>
    </div>
  </div>
)

const mapStateToProps = ({ assetsChart }) => ({
  timeRange: assetsChart.timeRange,
  currency: assetsChart.currency
})

const mapDispatchToProps = dispatch => ({
  handleSelectTimeRange: timeRange => dispatch(selectTimeRange(timeRange)),
  handleSelectCurrency: currency => dispatch(selectCurrency(currency))
})

export default connect(
  mapStateToProps,
  mapDispatchToProps
)(AssetsChartHeader)
