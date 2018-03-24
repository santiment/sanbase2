import React from 'react'
import { Link } from 'react-router-dom'
import './Footer.css'

const Footer = () => {
  return (
    <div className='sanbase-footer'>
      <div className='sanbase-footer__links'>
        <Link to={'/roadmap'}>Roadmap</Link>
        <Link to={'/faq'}>Faq</Link>
        <Link to={'/status'}>Status</Link>
        <Link to={'/contact'}>Contact</Link>
        <Link to={'/request_token'}>Request Token</Link>
      </div>
      <div className='sanbase-footer__greetings'>
        Brought to you by <a href='https://santiment.net'>Santiment</a>
      </div>
    </div>
  )
}

export default Footer
