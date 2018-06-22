import React from 'react'

export const ApiExplorer = (props) => {
  return (
    <div>
      <iframe
        src={`/graphiql${props.location.search}`}
        title='API explorer'
        width='100%'
        height='800px'
      />
    </div>
  )
}

export default ApiExplorer
