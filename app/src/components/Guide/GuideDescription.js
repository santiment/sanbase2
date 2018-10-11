import React from 'react'

const GuideDescription = ({ topic: { title, description } }) => (
  <div className='Guide__description'>
    <h3 className='Guide__title'>{title}</h3>
    <p className='Guide__text'>{description}</p>
  </div>
)

export default GuideDescription
