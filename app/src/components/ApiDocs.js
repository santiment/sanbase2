import React from 'react'
import './ApiDocs.css'

export const ApiDocs = (props) => {
  return (
    <div className='apidocs-container'>
      <iframe
        src='/apiexamples'
        title='API documentation'
        className='apidocs-iframe'
      />
    </div>
  )
}

export default ApiDocs
