import React from 'react'

export const SmoothDropdownContext = React.createContext()

const SmoothDropdown = ({ id, children }) => {
  const portal = document.createElement('ul')
  portal.classList.add('smooth-dropdown__list')
  return (
    <SmoothDropdownContext.Provider value={portal}>
      {children}
      <div className='morph-dropdown-wrapper SmoothDropdown' id={id}>
        <div
          className='dropdown-list smooth-dropdown'
          ref={node => node.appendChild(portal)}
        />
      </div>
    </SmoothDropdownContext.Provider>
  )
}

export default SmoothDropdown
