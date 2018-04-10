import React from 'react'
import Analytics from './../Analytics'

const ProjectChartMobile = ({
  historyTwitterData = {
    items: [],
    loading: true
  },
  ethPrice = {
    history: {
      items: [],
      loading: true
    }
  }
}) => {
  return (
    <div>
      <Analytics
        data={ethPrice.history}
        label='priceUsd'
        show='ETH Price'
      />
      <Analytics
        data={historyTwitterData}
        label='followersCount'
        show='last 7 days'
      />
    </div>
  )
}

export default ProjectChartMobile
