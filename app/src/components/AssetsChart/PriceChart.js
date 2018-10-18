import React from 'react'
import { Area } from 'recharts'

const priceChart = ({ selectedCurrency, data }) => (
  <Area
    type='linear'
    yAxisId='axis-price'
    xAxisId='axis-datetime'
    connectNulls={true}
    data={data}
    key={selectedCurrency}
    name={selectedCurrency}
    dot={false}
    strokeWidth={2}
    dataKey={selectedCurrency === 'USD' ? 'priceUsd' : 'priceBtc'}
    fill={'rgba(52, 171, 107, 0.03)'}
    stroke={'rgb(52, 171, 107)'}
  />
)

export default priceChart
