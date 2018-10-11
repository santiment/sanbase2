import React from 'react'
import DesktopMenuLinkContainer from './DesktopMenuLinkContainer'
import './DesktopAnalysisMenu.css'

const DesktopAnalysisMenu = () => (
  <div className='analysis-menu'>
    <DesktopMenuLinkContainer
      title='Insights'
      description='Record your observations, share them with the community if you’d like, and read Insights from others.'
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
      description='Get notifications when metrics for tokens you are tracking cross certain thresholds. Customize to your preferences.'
      linkIcon='signals'
      to='/signals'
    />
    <DesktopMenuLinkContainer
      title='Research tools'
      description='Advanced dashboards with experimental visualizations and more robust tools for experienced data scientists.'
      linkIcon='research'
      to='https://data.santiment.net'
    />
    <DesktopMenuLinkContainer
      title='Sanbase api'
      description='Access our data feeds to perform your own research and analysis, build UI tools... whatever you can imagine.'
      linkIcon='api'
      to='https://docs.santiment.net'
    />
  </div>
)

export default DesktopAnalysisMenu
