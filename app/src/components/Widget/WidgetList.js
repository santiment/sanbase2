import React from 'react'
import GetTotalMarketcap from '../TotalMarketcapWidget/GetTotalMarketcap'
import InsightsWidget from '../InsightsWidget/InsightsWidget'
import './WidgetList.scss'
const WidgetList = ({ type, isLoggedIn }) => {
  return (
    <div className='WidgetList'>
      <GetTotalMarketcap type={type} />
      {isLoggedIn && <InsightsWidget />}
    </div>
  )
}
export default WidgetList
