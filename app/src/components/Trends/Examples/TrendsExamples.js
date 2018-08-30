import React from 'react'
import TrendsExamplesItem from './TrendsExamplesItem'
import './TrendsExamples.css'

const examples = [
  { query: 'crypto', description: 'some description', settings: '' },
  { query: 'btc', description: 'some description', settings: '' },
  { query: 'eth', description: 'some description', settings: '' }
]

const TrendsExamples = () => {
  return (
    <ul className='TrendsExamples'>
      {examples.map(({ query, description, settings }, index) => (
        <TrendsExamplesItem
          key={index}
          query={query}
          description={description}
          settings={settings}
        />
      ))}
    </ul>
  )
}

export default TrendsExamples
