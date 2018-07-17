import React from 'react'
import './ApiExplorer.css'

export const ApiExplorer = props => {
  return (
    <div className='apiexplorer-container'>
      <iframe
        src={`/graphiql${props.location.search}`}
        title='API explorer'
        className='apiexplorer-iframe'
      />
    </div>
  )
}

export default ApiExplorer
