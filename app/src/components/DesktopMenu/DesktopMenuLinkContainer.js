import React from 'react'
import PropTypes from 'prop-types'
import { Link } from 'react-router-dom'
import './DesktopMenuLinkContainer.css'

const DesktopMenuLinkContainer = ({ title, description, linkIcon, to }) => {
  const Component = /^https?:\/\//.test(to) ? 'a' : Link

  return (
    <Component href={to} to={to} className='link-container'>
      <img
        className='link-icon'
        alt={`icon of ${linkIcon}`}
        src={require(`../../assets/top_menu_${linkIcon}.svg`)}
      />
      <div className='link-text'>
        <h3 className='link-title'>{title}</h3>
        <p className='link-description'>{description}</p>
      </div>
    </Component>
  )
}

DesktopMenuLinkContainer.propTypes = {
  title: PropTypes.string.isRequired,
  description: PropTypes.string.isRequired,
  linkIcon: PropTypes.string.isRequired,
  to: PropTypes.string.isRequired
}

export default DesktopMenuLinkContainer
