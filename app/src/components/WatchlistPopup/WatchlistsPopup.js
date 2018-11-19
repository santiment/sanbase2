import React from 'react'
import { graphql } from 'react-apollo'
import { connect } from 'react-redux'
import { compose } from 'recompose'
import moment from 'moment'
import { Popup, Button } from 'semantic-ui-react'
import { WatchlistGQL } from './WatchlistGQL'
import Watchlists, { hasAssetById } from './Watchlists'
import WatchlistsAnon from './WatchlistsAnon'
import * as actions from './../../actions/types'
import './WatchlistsPopup.css'

const POLLING_INTERVAL = 4000

const AddToListBtn = (
  <Button basic className='watchlists-button'>
    ADD TO WATCHLISTS
  </Button>
)

const WatchlistPopup = ({
  isNavigation = false,
  isLoading,
  isLoggedIn,
  projectId,
  slug,
  lists,
  trigger = AddToListBtn,
  watchlistUi,
  createWatchlist,
  removeAssetList,
  toggleConfirmDeleteAssetList,
  toggleAssetInList,
  children
}) => {
  return (
    <Popup
      className='watchlists-popup'
      content={
        isLoggedIn ? (
          children ? (
            React.cloneElement(children, {
              isLoading,
              projectId,
              createWatchlist,
              removeAssetList,
              toggleConfirmDeleteAssetList,
              toggleAssetInList,
              watchlistUi,
              slug,
              lists
            })
          ) : (
            <Watchlists
              isNavigation={isNavigation}
              isLoading={isLoading}
              projectId={projectId}
              createWatchlist={createWatchlist}
              removeAssetList={removeAssetList}
              toggleConfirmDeleteAssetList={toggleConfirmDeleteAssetList}
              toggleAssetInList={toggleAssetInList}
              watchlistUi={watchlistUi}
              slug={slug}
              lists={lists}
            />
          )
        ) : (
          <WatchlistsAnon />
        )
      }
      trigger={trigger}
      position='bottom center'
      on='click'
    />
  )
}

const sortWatchlists = (list, list2) =>
  moment.utc(list.insertedAt).diff(moment.utc(list2.insertedAt))

const mapStateToProps = state => {
  return {
    watchlistUi: state.watchlistUi
  }
}

const mapDispatchToProps = (dispatch, ownProps) => ({
  toggleAssetInList: ({ projectId, assetsListId, listItems, slug }) => {
    if (!projectId) return
    const isAssetInList = hasAssetById({
      listItems: ownProps.lists.find(list => list.id === assetsListId)
        .listItems,
      id: projectId
    })
    if (isAssetInList) {
      return dispatch({
        type: actions.USER_REMOVE_ASSET_FROM_LIST,
        payload: { projectId, assetsListId, listItems, slug }
      })
    } else {
      return dispatch({
        type: actions.USER_ADD_ASSET_TO_LIST,
        payload: { projectId, assetsListId, listItems, slug }
      })
    }
  },
  createWatchlist: payload =>
    dispatch({
      type: actions.USER_ADD_NEW_ASSET_LIST,
      payload
    }),
  removeAssetList: id =>
    dispatch({
      type: actions.USER_REMOVE_ASSET_LIST,
      payload: { id }
    }),
  toggleConfirmDeleteAssetList: id =>
    dispatch({
      type: actions.WATCHLIST_TOGGLE_CONFIRM_DELETE_MODAL,
      payload: { id }
    })
})

export default compose(
  graphql(WatchlistGQL, {
    name: 'Watchlists',
    skip: ({ isLoggedIn }) => !isLoggedIn,
    options: () => ({
      pollInterval: POLLING_INTERVAL,
      context: { isRetriable: true }
    }),
    props: ({ Watchlists }) => {
      const { fetchUserLists = [], loading = true } = Watchlists
      return {
        lists: [...fetchUserLists].sort(sortWatchlists),
        isLoading: loading
      }
    }
  }),
  connect(
    mapStateToProps,
    mapDispatchToProps
  )
)(WatchlistPopup)
