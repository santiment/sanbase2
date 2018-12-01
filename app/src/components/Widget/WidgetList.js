import React from 'react'
import GetTotalMarketcap from '../TotalMarketcapWidget/GetTotalMarketcap'
import InsightsWidget from '../InsightsWidget/InsightsWidget'
import LatestWatchlistsWidget from '../LatestWatchlistsWidget/LatestWatchlistsWidget'
import './WidgetList.scss'
const WidgetList = ({ type, isLoggedIn, listName }) => {
  return (
    <div className='WidgetList'>
      <GetTotalMarketcap type={type} listName={listName} />
      {isLoggedIn && <InsightsWidget />}
      <LatestWatchlistsWidget />
    </div>
  )
}
export default WidgetList
