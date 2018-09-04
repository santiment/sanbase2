import React from 'react'
import cx from 'classnames'
import './TrendsExploreSourcesFilter.css'

const sourceTitles = [
  'Telegram',
  'Reddit',
  'Professional Traders Chat',
  'Merged sources'
]

const TrendsExploreSourcesFilterItem = ({ title, disabled, onClick }) => {
  return (
    <button
      className={cx({
        'ui basic button': true,
        disabled: disabled,
        active: !disabled
      })}
      onClick={onClick}
    >
      <span>{title}</span>
    </button>
  )
}

const TrendsExploreSourcesFilter = () => {
  return (
    <div className='TrendsExploreSourcesFilter'>
      {sourceTitles.map((sourceTitle, index) => (
        <TrendsExploreSourcesFilterItem
          key={sourceTitle}
          disabled={index !== 3}
          title={sourceTitle}
        />
      ))}
    </div>
  )
}

export default TrendsExploreSourcesFilter
