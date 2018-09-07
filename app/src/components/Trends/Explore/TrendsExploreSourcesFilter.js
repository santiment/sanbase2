import React from 'react'
import cx from 'classnames'
import { Source } from '../trendsUtils'
import './TrendsExploreSourcesFilter.css'

const TrendsExploreSourcesFilterItem = ({
  title,
  disabled,
  active,
  dataSource,
  onClick
}) => {
  return (
    <button
      className={cx({
        'ui basic button': true,
        disabled: disabled,
        active: active
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
          active={selectedSources.includes(source)}
          disabled={selectedSources.includes('merged') && source !== 'merged'}
          dataSource={source}
          title={Source[source]}
          onClick={handleSourceSelect}
        />
      ))}
    </div>
  )
}

export default TrendsExploreSourcesFilter
