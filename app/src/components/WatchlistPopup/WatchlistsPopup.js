import React from 'react'
import { graphql } from 'react-apollo'
import { compose } from 'recompose'
import moment from 'moment'
import { Popup, Button } from 'semantic-ui-react'
import { WatchlistGQL } from './WatchlistGQL'
import Watchlists from './Watchlists'
import './WatchlistsPopup.css'

const POLLING_INTERVAL = 2000

const AddToListBtn = (
  <Button basic color='purple'>
    add to list
  </Button>
)

const WatchlistPopup = ({
  isNavigation = false,
  isLoading,
  isLoggedIn,
  projectId,
  slug,
  lists,
  trigger = AddToListBtn
}) => {
  return (
    <Popup
      className='watchlists-popup'
      content={
        <Watchlists
          isNavigation={isNavigation}
          isLoading={isLoading}
          projectId={projectId}
          slug={slug}
          lists={lists}
        />
      }
      trigger={trigger}
      position='bottom center'
      on='click'
    />
  )
}

const sortWatchlists = (list, list2) =>
  moment.utc(list.insertedAt).diff(moment.utc(list2.insertedAt))

export default compose(
  graphql(WatchlistGQL, {
    name: 'Watchlists',
    options: ({ isLoggedIn }) => ({
      skip: !isLoggedIn,
      pollInterval: POLLING_INTERVAL
    }),
    props: ({ Watchlists }) => {
      const { fetchUserLists = [], loading = true } = Watchlists
      return {
        lists: [...fetchUserLists].sort(sortWatchlists),
        isLoading: loading
      }
    }
  })
)(WatchlistPopup)
