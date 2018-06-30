import React from 'react'
import { Link } from 'react-router-dom'
import './Footer.css'

const Footer = () => {
  return (
    <div className='sanbase-footer'>
      <div className='sanbase-footer__links'>
        <Link to={'/roadmap'}>Roadmap</Link>
        <Link to={'/status'}>Status</Link>
        <a href='mailto:info@santiment.net'>Contact</a>
        <Link to={'/privacy-policy'}>Privacy</Link>
        <a href='https://docs.google.com/forms/d/e/1FAIpQLSeFuCxjJjId98u1Bp3qpXCq2A9YAQ02OEdhOgiM9Hr-rMDxhQ/viewform'>
          Request Token
        </a>
      </div>
      <div className='sanbase-footer__greetings'>
        Brought to you by &nbsp;
        <a
          href='https://santiment.net'
          rel='noopener noreferrer'
          target='_blank'>Santiment</a>
      </div>
      <div>ver. {process.env.REACT_APP_VERSION}</div>
      <div className='cashflow-indev-message'>
        NOTE: This app is an early release.
        We give no guarantee data is correct as we are in active development.
      </div>
    </div>
  )
}

export default Footer
