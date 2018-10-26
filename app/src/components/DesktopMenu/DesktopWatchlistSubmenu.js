import React, { Fragment } from 'react'
import { Link } from 'react-router-dom'
import { graphql } from 'react-apollo'
import { connect } from 'react-redux'
import { compose } from 'recompose'
import { WatchlistGQL } from '../WatchlistPopup/WatchlistGQL'

import styles from './DesktopProfileMenu.module.css'

const MAX_ITEMS_NUMBER = 3

const DesktopWatchlistSubmenu = ({ watchlists }) => {
  if (watchlists.length === 0) {
    return null
  }

  return (
    <Fragment>
      <hr
        style={{
          margin: '10px 0 0'
        }}
      />
      <h3>Watchlists</h3>
      {watchlists.map(({ name, id, listItems }) => (
        <Link
          key={id}
          className={`${styles.button} ${styles.item}`}
          to={`/assets/list?name=${name}@${id}`}
        >
          <span className={styles.name}>{name}</span>
          <span className={styles.amount}>{listItems.length}</span>
        </Link>
      ))}
    </Fragment>
  )
}

DesktopWatchlistSubmenu.defaultProps = {
  watchlists: []
}

const mapStateToProps = state => {
  return {
    isLoggedIn: !!state.user.token
  }
}

const enhance = compose(
  connect(mapStateToProps),
  graphql(WatchlistGQL, {
    name: 'Watchlists',
    skip: ({ isLoggedIn }) => !isLoggedIn,
    props: ({ Watchlists }) => {
      const { fetchUserLists = [] } = Watchlists
      return {
        watchlists: fetchUserLists.slice(0, MAX_ITEMS_NUMBER)
      }
    }
  })
)

export default enhance(DesktopWatchlistSubmenu)
