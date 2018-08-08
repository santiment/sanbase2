import React from 'react'
import { graphql } from 'react-apollo'
import { compose } from 'recompose'
import { Popup, Button } from 'semantic-ui-react'
import { AssetsListGQL } from './AssetsListGQL'
import Watchlists from './Watchlists'
import './WatchlistsPopup.css'

const POLLING_INTERVAL = 2000

const AddToListBtn = (
  <Button basic color='purple'>
    add to list
  </Button>
)

const AssetsListPopup = ({
  isNavigation = false,
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

export default compose(
  graphql(AssetsListGQL, {
    name: 'Watchlists',
    options: ({ isLoggedIn }) => ({
      skip: !isLoggedIn,
      pollInterval: POLLING_INTERVAL
    }),
    props: ({ Watchlists }) => {
      const { fetchUserLists = [] } = Watchlists
      return {
        lists: fetchUserLists
      }
    }
  })
)(AssetsListPopup)
