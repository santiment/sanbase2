import React from 'react'
import GetTotalMarketcap from '../TotalMarketcapWidget/GetTotalMarketcap'
import InsightsWidget from '../InsightsWidget/InsightsWidget'
import LatestWatchlistsWidget from '../LatestWatchlistsWidget/LatestWatchlistsWidget'
import './WidgetList.scss'
const WidgetList = ({ type, isLoggedIn }) => {
  return (
    <div className='WidgetList'>
      <GetTotalMarketcap type={type} />
      {isLoggedIn && <InsightsWidget />}
      <LatestWatchlistsWidget />
    </div>
  )
}
export default WidgetList
