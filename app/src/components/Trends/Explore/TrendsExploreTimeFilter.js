import React from 'react'
import TrendsExploreTimeFilterOption from './TrendsExploreTimeFilterOption'
import './TrendsExploreTimeFilter.css'

const timeOptions = ['1w', '1m', '3m', '6m', '1y', 'all']

const TrendsExploreTimeFilter = ({ selectedOption }) => {
  return (
    <ul className='TrendsExploreTimeFilter'>
      {timeOptions.map(option => (
        <TrendsExploreTimeFilterOption
          key={option}
          label={option}
          isActive={selectedOption === option}
          // onClick={() => console.log(option)}
        />
      ))}
    </ul>
  )
}

export default TrendsExploreTimeFilter
