import React from 'react'
import './TrendsExploreSourcesFilter.css'

const sourceTitles = [
  'Telegram',
  'Reddit',
  'Professional Traders Chat',
  'Merged sources'
]

const TrendsExploreSourcesFilterItem = ({ title, onClick }) => {
  return (
    <button className='TrendsExploreSourcesFilter__item' onClick={onClick}>
      <span>{title}</span>
    </button>
  )
}

const TrendsExploreSourcesFilter = () => {
  return (
    <div className='TrendsExploreSourcesFilter'>
      {sourceTitles.map(sourceTitle => (
        <TrendsExploreSourcesFilterItem key={sourceTitle} title={sourceTitle} />
      ))}
    </div>
  )
}

export default TrendsExploreSourcesFilter
