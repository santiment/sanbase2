import React from 'react'
import PropTypes from 'prop-types'
import { FontAwesomeIcon } from '@fortawesome/react-fontawesome'
import Input from '../Input/Input'
import { faSearch } from '@fortawesome/free-solid-svg-icons'
import styles from './Search.scss'

const Search = ({ iconPosition = 'left', className = '', ...props }) => {
  return (
    <div className={styles.wrapper}>
      <Input
        className={`${styles.input} ${styles[iconPosition]}`}
        placeholder='Search...'
        {...props}
      />
      <FontAwesomeIcon
        icon={faSearch}
        className={`${styles.icon} ${styles[iconPosition]}`}
      />
    </div>
  )
}

Search.propTypes = {
  iconPosition: PropTypes.oneOf(['left', 'right'])
}

export default Search
