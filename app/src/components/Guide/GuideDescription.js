import React from 'react'

const GuideDescription = ({ topic }) => {
  return (
    <div className='Guide__description'>
      <h3 className='Guide__title'>{topic.title}</h3>
      <p className='Guide__text'>{topic.description}</p>
    </div>
  )
}

export default GuideDescription
