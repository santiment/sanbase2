import React from 'react'
import DesktopMenuLinkContainer from './DesktopMenuLinkContainer'
import './DesktopAnalysisMenu.css'

const DesktopAnalysisMenu = () => (
  <div className='analysis-menu'>
    <div className='analysis-menu-row'>
      <DesktopMenuLinkContainer
        title='Insights'
        description='Record your observations, share them with the community if you’d like, and read Insights from others. '
        linkIcon='insights'
        to='/insights'
      />
      <DesktopMenuLinkContainer
        title='Research tools'
        description='Advanced dashboards with experimental visualizations and more robust tools for experienced data scientists.'
        linkIcon='research'
        to='https://data.santiment.net'
      />
    </div>
    <div className='analysis-menu-row'>
      <DesktopMenuLinkContainer
        title='signals'
        description='Get notifications when metrics for tokens you are tracking cross certain thresholds. Customize to your preferences.'
        linkIcon='signals'
        to='/signals'
      />
      <DesktopMenuLinkContainer
        title='Sanbase api'
        description='Access our data feeds to perform your own research and analysis, build UI tools... whatever you can imagine.'
        linkIcon='api'
        to='https://docs.santiment.net'
      />
    </div>
  </div>
)

export default DesktopAnalysisMenu
