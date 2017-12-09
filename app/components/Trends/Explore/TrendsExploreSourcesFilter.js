import React from 'react'
import cx from 'classnames'
import { Source, SourceColor } from '../trendsUtils'
import './TrendsExploreSourcesFilter.css'
import './TrendsExploreSourcesFilterItem.css'

const TrendsExploreSourcesFilterItem = ({
  title,
  disabled,
  active,
  dataSource,
  onClick,
  borderColor
}) => {
  return (
    <button
      className={cx({
        'TrendsExploreSourcesFilterItem ui basic button': true,
        disabled: disabled,
        active: active
      })}
      onClick={onClick}
      data-source={dataSource}
    >
      <span style={{ borderColor }}>{title}</span>
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
          borderColor={SourceColor[source]}
        />
      ))}
    </div>
  )
}

export default TrendsExploreSourcesFilter
