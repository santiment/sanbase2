import React from 'react'
import TrendsExploreTimeFilterOption from './TrendsExploreTimeFilterOption'
import './TrendsExploreTimeFilter.css'

const timeOptions = ['all', '1y', '6m', '3m', '1m', '1w']

const TrendsExploreTimeFilter = ({ selectedOption }) => {
  return (
    <ul className='TrendsExploreTimeFilter'>
      {timeOptions.map(option => (
        <TrendsExploreTimeFilterOption
          key={option}
          label={option}
          isActive={selectedOption === option}
          onClick={() => console.log(option)}
        />
      ))}
    </ul>
  )
}

export default TrendsExploreTimeFilter
