import React, { Component } from 'react'
import './SmoothDropdown.css'

export const SmoothDropdownContext = React.createContext({
  portal: document.createElement('ul'),
  currentDrop: null,
  changeDrop: id => {}
})

// const SmoothDropdown = ({ id, children }) => {
//   const portal = document.createElement('ul')
//   portal.classList.add('smooth-dropdown__list')
//   return (
//     <SmoothDropdownContext.Provider value={portal}>
//       {children('tester')}
//       <div className='morph-dropdown-wrapper SmoothDropdown' id={id}>
//         <div
//           className='dropdown-list smooth-dropdown'
//           ref={node => node.appendChild(portal)}
//         />
//       </div>
//     </SmoothDropdownContext.Provider>
//   )
// }

class SmoothDropdown extends Component {
  myRef = React.createRef()

  state = {
    currentDrop: null
  }

  changeDrop = id => {
    console.log(id)
    this.setState(prevState => ({
      ...prevState,
      currentDrop: id
    }))
  }

  render () {
    const { children, id } = this.props
    const { currentDrop } = this.state
    // portal.classList.add('smooth-dropdown__list')
    return (
      <SmoothDropdownContext.Provider
        value={{
          ...this.state,
          portal: this.myRef.current,
          changeDrop: this.changeDrop
        }}
      >
        {children('tester')}
        <div className='morph-dropdown-wrapper SmoothDropdown' id={id}>
          <div className='dropdown-list smooth-dropdown'>
            {/* // ref={node => node.appendChild(portal)} */}
            <ul ref={this.myRef} />
          </div>
        </div>
      </SmoothDropdownContext.Provider>
    )
  }
}

export default SmoothDropdown
