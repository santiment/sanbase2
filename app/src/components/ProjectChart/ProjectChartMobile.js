import React, { Fragment } from 'react'
import Analytics from './../Analytics'

const ProjectChartMobile = ({
  historyTwitterData = {
    items: [],
    loading: true
  },
  price = {
    history: {
      items: [],
      loading: true
    }
  }
}) => {
  return (
    <Fragment>
      <Analytics
        data={price.history}
        label='priceUsd'
        show='Price'
        chart={{
          type: 'line',
          color: 'rgba(38, 43, 51)',
          fill: true,
          borderWidth: 1,
          pointBorderWidth: 2,
          referenceLine: {
            y: 2,
            label: 'ICO price'
          }
        }}
      />
      <Analytics
        data={price.history}
        label='volume'
        chart={{
          type: 'bar',
          color: 'rgba(38, 43, 51)',
          fill: false,
          borderWidth: 1,
          pointBorderWidth: 2,
          withMiniMap: true
        }}
        show='Volume'
      />
      <Analytics
        data={price.history}
        label='marketcap'
        show='Marketcap'
      />
      <Analytics
        data={historyTwitterData}
        label='followersCount'
        show='last 7 days'
      />
    </Fragment>
  )
}

export default ProjectChartMobile
