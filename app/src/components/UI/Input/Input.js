import React from 'react'
import styles from './Input.scss'

const Input = ({ value, inplace, className = '', ...props }) => {
  return (
    <input
      type='text'
      className={`${styles.input} ${
        inplace ? styles['inplace'] : ''
      } ${className}`}
      value={value}
      {...props}
    />
  )
}

export default Input
