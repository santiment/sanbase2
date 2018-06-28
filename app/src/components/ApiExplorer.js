import React from 'react'
import './ApiExplorer.css'
import {isMobileSafari} from 'react-device-detect'

export const ApiExplorer = (props) => {
  return (
    <div className='apiexplorer-container'>
      {
        isMobileSafari ? (
          <iframe
            scrolling='no'
            src={`/graphiql${props.location.search}`}
            title='API explorer'
            className='apiexplorer-iframe-iphone'
          />
        ) : (
          <iframe
            src={`/graphiql${props.location.search}`}
            title='API explorer'
            className='apiexplorer-iframe'
          />
        )
      }
    </div>
  )
}

export default ApiExplorer
