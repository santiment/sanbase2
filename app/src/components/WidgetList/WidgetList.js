import React from 'react'
import TotalMarketcapWidget from '../TotalMarketcapWidget/TotalMarketcapWidget'
import InsightsWidget from '../InsightsWidget/InsightsWidget'
import './WidgetList.scss'

const WidgetList = () => {
  return (
    <div className='WidgetList'>
      <TotalMarketcapWidget />
      <InsightsWidget />
    </div>
  )
}

export default WidgetList
