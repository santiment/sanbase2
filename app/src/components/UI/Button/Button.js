import React from 'react'
import PropTypes from 'prop-types'
import styles from './Button.scss'

const getBorderedStyles = border => `${styles['border']} ${styles[border]}`
const getFillStyles = fill => `${styles['fill']} ${styles[fill]}`

const Button = ({
  children,
  fill,
  border,
  onClick,
  className = '',
  ...props
}) => {
  console.log(styles)
  return (
    <button
      onClick={onClick}
      className={`${styles.btn} ${
        fill ? getFillStyles(fill) : getBorderedStyles(border)
      } ${className} `}
      {...props}
    >
      {children}
    </button>
  )
}

Button.propTypes = {
  fill: PropTypes.oneOf(['grey', 'positive', 'negative', 'purple']),
  border: PropTypes.oneOf(['positive', 'negative', 'purple'])
}

export default Button
