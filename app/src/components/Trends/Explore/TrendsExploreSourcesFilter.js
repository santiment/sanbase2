import React from 'react'
import cx from 'classnames'
import { Source } from '../trendsUtils'
import './TrendsExploreSourcesFilter.css'

// const sourceTitles = [
//   'Telegram',
//   'Reddit',
//   'Professional Traders Chat',
//   'Merged sources'
// ]

const TrendsExploreSourcesFilterItem = ({
  title,
  disabled,
  dataSource,
  onClick
}) => {
  return (
    <button
      className={cx({
        'ui basic button': true,
        disabled: disabled,
        active: !disabled
      })}
      onClick={onClick}
      data-source={dataSource}
    >
      <span>{title}</span>
    </button>
  )
}

const TrendsExploreSourcesFilter = ({
  selectedSources,
  handleSourceSelect
}) => {
  return (
    <div className='TrendsExploreSourcesFilter'>
      {Object.keys(Source).map(source => (
        <TrendsExploreSourcesFilterItem
          key={source}
          dataSource={source}
          title={Source[source]}
          onClick={handleSourceSelect}
        />
      ))}
    </div>
  )
}

export default TrendsExploreSourcesFilter
