import React from 'react'
import DesktopMenuLinkContainer from './DesktopMenuLinkContainer'
import './DesktopAnalysisMenu.css'

const DesktopAnalysisMenu = () => (
  <div className='analysis-menu'>
    <DesktopMenuLinkContainer
      title='Insights'
      description='Record your ideas as a private journal, or share them with the community'
      linkIcon='insights'
      to='/insights'
    />
    <DesktopMenuLinkContainer
      title='Trends'
      description='Plot usage of terms in social media against BTC or ETH price'
      linkIcon='trends'
      to='/trends'
    />
    <DesktopMenuLinkContainer
      title='signals'
      description='Get notifications when metrics cross certain thresholds (SOON)'
      linkIcon='signals'
      to='/signals'
    />
    <DesktopMenuLinkContainer
      title='Research tools'
      description='Experimental visualizations and data feeds (BETA)'
      linkIcon='research'
      to='https://data.santiment.net'
    />
    <DesktopMenuLinkContainer
      title='Sanbase api'
      description='Access our data feeds and code libraries for your own projects'
      linkIcon='api'
      to='https://docs.santiment.net'
    />
  </div>
)

export default DesktopAnalysisMenu
