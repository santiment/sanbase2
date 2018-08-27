import React from 'react'
import PropTypes from 'prop-types'
import { Link } from 'react-router-dom'
import linkIcon from './../assets/top_menu_insights.svg'
import './DesktopMenuLinkContainer.css'

const DesktopMenuLinkContainer = ({ title, description, linkIcon, to }) => (
  <Link to={to} className='link-container'>
    <img
      className='link-icon'
      src={require(`../assets/top_menu_${linkIcon}.svg`)}
    />
    <div className='link-text'>
      <h3 className='link-title'>{title}</h3>
      <p className='link-description'>{description}</p>
    </div>
  </Link>
)

DesktopMenuLinkContainer.propTypes = {
  title: PropTypes.string.isRequired,
  description: PropTypes.string.isRequired,
  linkIcon: PropTypes.string.isRequired,
  to: PropTypes.string.isRequired
}

export default DesktopMenuLinkContainer
