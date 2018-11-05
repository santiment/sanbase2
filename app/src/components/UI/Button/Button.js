import React from 'react'
import PropTypes from 'prop-types'
import styles from './Button.scss'

const getBorderedStyles = border => `${styles['border']} ${styles[border]}`
const getFillStyles = fill => `${styles['fill']} ${styles[fill]}`

const Button = ({ children, fill, border, onClick, className = '' }) => {
  return (
    <button
      onClick={onClick}
      className={`${styles.btn} ${
        fill ? getFillStyles(fill) : getBorderedStyles(border)
      } ${className} `}
    >
      {children}
    </button>
  )
}

Button.propTypes = {
  fill: PropTypes.oneOf(['positive', 'negative']),
  border: PropTypes.oneOf(['positive', 'negative'])
}

export default Button
