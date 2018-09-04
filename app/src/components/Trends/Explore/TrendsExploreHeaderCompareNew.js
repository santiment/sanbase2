import React from 'react'

const TrendsExploreHeaderCompareNew = () => {
  return (
    <div
      className='TrendsExploreHeaderCompareNew'
      style={{
        fontSize: '2em',
        color: '#888',
        outline: 'none',
        background: 'none',
        border: 'none',
        flex: '50%'
      }}
      onFocus={evt => console.log(evt.currentTarget)}
    >
      + New comparison
    </div>
  )
}

export default TrendsExploreHeaderCompareNew
