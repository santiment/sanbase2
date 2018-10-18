import React, { Fragment } from 'react'
import { Link } from 'react-router-dom'
import { graphql } from 'react-apollo'
import { WatchlistGQL } from '../WatchlistPopup/WatchlistGQL'

import styles from './DesktopProfileMenu.module.css'

DesktopWatchlistSubmenu.defaultProps = {
  watchlists: []
}

function DesktopWatchlistSubmenu ({ watchlists }) {
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
          className={styles.button}
          to={`/assets/list?name=${name}@${id}`}
        >
          {name}
          <span className={styles.amount}>{listItems.length}</span>
        </Link>
      ))}
    </Fragment>
  )
}

export default graphql(WatchlistGQL, {
  name: 'Watchlists',
  options: ({ isLoggedIn }) => ({
    skip: !isLoggedIn
  }),
  props: ({ Watchlists }) => {
    const { fetchUserLists = [] } = Watchlists
    return {
      watchlists: fetchUserLists.slice(0, 3)
    }
  }
})(DesktopWatchlistSubmenu)
