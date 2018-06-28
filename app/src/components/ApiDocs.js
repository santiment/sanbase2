import React from 'react'
import './ApiDocs.css'
import {isMobile, isIOS} from 'react-device-detect'

export const ApiDocs = (props) => {
  return (
    <div className='apidocs-container'>
      {
        isMobile && isIOS ? (
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
