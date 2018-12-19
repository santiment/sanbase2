import React from 'react'
import PropTypes from 'prop-types'
import styles from './Panel.scss'

const Panel = ({ popup, children, className = '', ...props }) => {
  return (
    <div
      className={`${styles.panel} ${popup ? styles.popup : ''} ${className}`}
      {...props}
    >
      {children}
    </div>
  )
}

Panel.propTypes = {
  popup: PropTypes.bool
}

export default Panel
