import React from 'react'
import { withRouter } from 'react-router-dom'
import { graphql } from 'react-apollo'
import { Button, Popup } from 'semantic-ui-react'
import cx from 'classnames'
import * as qs from 'query-string'
import { compose } from 'recompose'
import copy from 'copy-to-clipboard'
import { updateUserListGQL, fetchUserListsGQL } from './watchlistShareGQL'
import styles from './WatchlistShare.module.css'

const copyUrl = () => {
  copy(window.location.href + '#shared')
}

const WatchlistShare = ({
  isPublic,
  toggleWatchlistPublicity,
  watchlistId
}) => (
  <div
    className={cx({
      [styles.wrapper]: true,
      [styles.public]: isPublic
    })}
  >
    <Button
      toggle
      active={isPublic}
      style={{ boxShadow: 'none !important' }}
      onClick={() => {
        toggleWatchlistPublicity({
          variables: { id: parseInt(watchlistId, 10), isPublic: !isPublic }
        }).catch(error => {
          alert('Error in publicity query: ', error)
        })
      }}
      className={styles.publicityBtn}
    >
      {isPublic ? 'Public' : 'Private'}
    </Button>

    <Popup
      trigger={
        <Button
          style={{ boxShadow: 'none !important' }}
          icon='linkify'
          className={styles.linkCopy}
          onClick={copyUrl}
        />
      }
      content='Click to copy the watchlist link'
      inverted
    />
  </div>
)

const enhance = compose(
  withRouter,
  graphql(updateUserListGQL, {
    name: 'toggleWatchlistPublicity'
  }),
  graphql(fetchUserListsGQL, {
    name: 'fetchUserLists',
    skip: ({ location: { search } }) => {
      const queryParams = qs.parse(search)
      return !(queryParams.name && queryParams.name.includes('@'))
    },
    props: ({ fetchUserLists, ownProps }) => {
      const { fetchUserLists: watchlists } = fetchUserLists
      const {
        location: { search }
      } = ownProps
      const parsedQS = qs.parse(search)

      if (!watchlists || !parsedQS.name) {
        return {}
      }
      const [, watchlistId] = parsedQS.name.split('@')
      const foundUserWatchlist = watchlists.find(
        watchlist => watchlist.id === watchlistId
      )

      if (!foundUserWatchlist) {
        return {}
      }

      return {
        isPublic: foundUserWatchlist.isPublic,
        watchlistId
      }
    }
  })
)

export default enhance(WatchlistShare)
