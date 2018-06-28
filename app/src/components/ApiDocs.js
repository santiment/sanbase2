import React from 'react'
import './ApiDocs.css'
import {isMobileSafari} from 'react-device-detect';

export const ApiDocs = (props) => {
  return (
    <div className='apidocs-container'>
      {
        isMobileSafari ? (
          <iframe
            scrolling='no'
            src='/apiexamples'
            title='API documentation'
            className='apidocs-iframe-iphone'
          />
        ) : (
          <iframe
            src='/apiexamples'
            title='API documentation'
            className='apidocs-iframe'
          />
        )
      }
    </div>
  )
}

export default ApiDocs
