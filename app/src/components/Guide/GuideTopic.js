import React from 'react'

const GuideTopic = ({ topic, isActive, onClick }) => {
  return (
    <li
      className={`Guide__topic ${isActive ? 'Guide__topic_active' : ''}`}
      onClick={() => onClick(topic)}
    >
      <button>{topic.title}</button>
    </li>
  )
}

export default GuideTopic
