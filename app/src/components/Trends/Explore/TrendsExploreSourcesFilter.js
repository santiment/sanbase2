import React from 'react'
import './TrendsExploreSourcesFilter.css'

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
      <TrendsExploreSourcesFilterItem title='Telegram' />
      <TrendsExploreSourcesFilterItem title='Reddit' />
      <TrendsExploreSourcesFilterItem title='Professional Traders Chat' />
      <TrendsExploreSourcesFilterItem title='Merged sources' />
    </div>
  )
}

export default TrendsExploreSourcesFilter
