import React from 'react'
import PropTypes from 'prop-types'
import { FontAwesomeIcon } from '@fortawesome/react-fontawesome'
import Input from '../Input/Input'
import { faSearch } from '@fortawesome/free-solid-svg-icons'
import styles from './Search.scss'

const Search = ({ iconPosition = 'left', className = '', ...props }) => {
  return (
    <div className={styles.wrapper}>
      <FontAwesomeIcon
        icon={faSearch}
        className={`${styles.icon} ${styles[iconPosition]}`}
      />
      <Input
        className={styles[iconPosition + '-input']}
        placeholder='Search...'
        {...props}
      />
    </div>
  )
}

Search.propTypes = {
  iconPosition: PropTypes.oneOf(['left', 'right'])
}

export default Search
