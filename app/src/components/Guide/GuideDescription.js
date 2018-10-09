import React from 'react'

const GuideDescription = ({ topic }) => {
  return (
    <div className='Guide__description'>
      <h3 className='Guide__title'>{topic.title}</h3>
    </div>
  )
}

export default GuideDescription
