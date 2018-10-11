import React from 'react'
import logo from '../assets/logo.png'

const PageLoader = () => (
  <div className='page'>
    <div
      style={{
        display: 'flex',
        justifyContent: 'center',
        alignItems: 'center',
        flexDirection: 'column',
        height: '50vh'
      }}
    >
      <img src={logo} width='44' height='44' alt='SANbase' />
      Loading ...
    </div>
  </div>
)

export default PageLoader
