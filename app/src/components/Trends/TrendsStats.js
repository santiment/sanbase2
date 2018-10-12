import React from 'react'
import GetTrendsStats from './GetTrendsStats'

const TrendsStatsLoader = () => ''

const TrendsStats = ({ timeRange }) => (
  <GetTrendsStats
    timeRange={timeRange}
    render={({ stats, isLoading }) => {
      if (isLoading) {
        return <TrendsStatsLoader />
      } else {
        return (
          <div style={{ background: '#f5f9ff99' }}>
            <hr />
            <strong style={{ marginLeft: 40 }}>
              These stats were compiled searching:
            </strong>
            <div style={{ display: 'flex', marginTop: 0 }}>
              <ul>
                <li>{stats.documentsCount} messages </li>
                <li>{stats.averageDocumentsPerDay} average messages per day</li>
              </ul>
              <ul>
                <li>{stats.telegramChannelsCount} telegram channels</li>
                <li>{stats.subredditsCount} subreddits</li>
              </ul>
            </div>
          </div>
        )
      }
    }}
  />
)

export default TrendsStats
