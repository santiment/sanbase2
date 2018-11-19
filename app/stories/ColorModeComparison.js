import React from 'react'
import './ColorModeComparison.css'

const ColorModeComparison = ({ children }) => {
  const elements = children.reduce
    ? children.reduce((acc, child) => {
      return [...acc, child, <div className='br' />]
    }, [])
    : children

  return (
    <div className='ColorModeComparison'>
      <div className='ColorModeComparison__column'>
        <h2 className='ColorModeComparison__title'>Day mode</h2>
        {elements}
      </div>
      <div className='ColorModeComparison__column night-mode'>
        <h2 className='ColorModeComparison__title'>Night mode</h2>
        {elements}
      </div>
    </div>
  )
}

export default ColorModeComparison
