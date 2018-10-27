import React from 'react'
import GetTotalMarketcap from '../TotalMarketcapWidget/GetTotalMarketcap'
import InsightsWidget from '../InsightsWidget/InsightsWidget'
import './WidgetList.scss'
const WidgetList = () => {
  return (
    <div className='WidgetList'>
      <GetTotalMarketcap type='all' />
      <InsightsWidget />
    </div>
  )
}
export default WidgetList
