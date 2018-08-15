import React from 'react'

export const SmoothDropdownContext = React.createContext()

const SmoothDropdown = ({ id, children }) => {
  const portal = document.createElement('div')
  return (
    <SmoothDropdownContext.Provider value={portal}>
      {children}
      <div
        className='SmoothDropdown'
        id={id}
        ref={node => node.appendChild(portal)}
      />
    </SmoothDropdownContext.Provider>
  )
}

export default SmoothDropdown
