import React, { Fragment } from 'react'

export const ApiExplorer = (props) => {
  return (
    <div>
      <iframe src={`/graphiql${props.location.search}`} width="100%" height="800px"></iframe>
    </div>
  )
}

export default ApiExplorer
