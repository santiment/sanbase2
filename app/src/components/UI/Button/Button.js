import React from 'react'
import styles from './Button.module.css'
const Button = ({ children, fill, onClick, className = '' }) => {
  console.log(styles)
  return (
    <button
      onClick={onClick}
      className={`${styles.btn} ${styles[fill]} ${className}`}
    >
      {children}
    </button>
  )
}

export default Button
