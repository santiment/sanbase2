import React, { Component } from 'react'
import './SmoothDropdown.css'

export const SmoothDropdownContext = React.createContext({
  portal: document.createElement('ul'),
  currentTrigger: null,
  changeDrop: id => {},
  hideDrop: () => {}
})

const dropdowns = new WeakMap()

export const createDrop = (trigger, dropdown) =>
  trigger && dropdowns.set(trigger, dropdown)

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
    currentTrigger: null
  }

  // changeDrop = id => {
  //   console.log(id)
  //   this.setState(prevState => ({
  //     ...prevState,
  //     currentTrigger: id
  //   }))
  // }
  changeDrop = trigger => {
    // console.log(trigger)
    this.setState(() => {
      this.calculateGeometry()
      return {
        currentTrigger: trigger
      }
    })
  }

  hideDrop = () => {
    const { currentTrigger } = this.state
    const selectedDropdown = dropdowns.get(currentTrigger)
    if (!selectedDropdown) return
    selectedDropdown.classList.remove('active')
    selectedDropdown.classList.remove('is-dropdown-visible')
  }

  calculateGeometry () {
    const { currentTrigger } = this.state
    const selectedDropdown = dropdowns.get(currentTrigger)
    if (!selectedDropdown) return
    const selectedDropdownHeight = selectedDropdown.offsetHeight
    const selectedDropdownWidth = selectedDropdown.firstElementChild.clientWidth
    // .innerWidth()
    const selectedDropdownLeft =
      currentTrigger.getBoundingClientRect().left +
      currentTrigger.offsetWidth / 2 -
      selectedDropdownWidth / 2

    // console.log(
    //   selectedDropdownHeight,
    //   selectedDropdownWidth,
    //   selectedDropdownLeft
    // )
    this.updateDropdown(
      selectedDropdown,
      selectedDropdownHeight,
      selectedDropdownWidth,
      selectedDropdownLeft
    )

    selectedDropdown.classList.add('is-dropdown-visible')
    selectedDropdown.classList.add('active')
  }

  updateDropdown (dropdown, height, width, left) {
    const dropdownList = document.querySelector('.dropdown-list')
    dropdownList.style.transform = 'translateX(' + left + 'px)'
    dropdownList.style.width = width + 'px'
    dropdownList.style.height = height + 'px'
  }

  render () {
    const { children, id } = this.props
    const { currentTrigger } = this.state
    // portal.classList.add('smooth-dropdown__list')
    return (
      <SmoothDropdownContext.Provider
        value={{
          ...this.state,
          portal: this.myRef.current,
          changeDrop: this.changeDrop,
          hideDrop: this.hideDrop
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
