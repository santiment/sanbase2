import Raven from 'raven-js'
import { Observable } from 'rxjs'
import { showNotification } from './../actions/rootActions'
import { WatchlistGQL } from './../components/WatchlistPopup/WatchlistGQL'
import { updateUserListGQL } from './addAssetToWatchlistEpic'
import * as actions from './../actions/types'

const removeAssetFromWatchlist = (action$, store, { client }) =>
  action$
    .ofType(actions.USER_REMOVE_ASSET_FROM_LIST)
    .debounceTime(200)
    .mergeMap(action => {
      const { assetsListId, listItems, projectId } = action.payload
      const newListItems = listItems
        .map(val => {
          return { project_id: +val.project.id }
        })
        .reduce((acc, val) => {
          if (val.project_id !== +projectId) {
            return [...acc, val]
          }
          return acc
        }, [])
      const mutationPromise = client.mutate({
        mutation: updateUserListGQL,
        variables: {
          listItems: newListItems,
          id: +assetsListId
        },
        update: (store, { data: { updateUserList } }) => {
          const data = store.readQuery({ query: WatchlistGQL })
          const index = data.fetchUserLists.findIndex(
            list => list.id === updateUserList.id
          )
          data.fetchUserLists[index] = updateUserList
          store.writeQuery({ query: WatchlistGQL, data })
        }
      })
      return Observable.from(mutationPromise)
        .mergeMap(({ data }) => {
          const assetSlug = action.payload.slug
          const watchlistName = data.updateUserList.name
          return Observable.merge(
            Observable.of({
              type: actions.USER_REMOVED_ASSET_FROM_LIST_SUCCESS
            }),
            Observable.of(
              showNotification(
                `Removed "${assetSlug}" from the list "${watchlistName}"`
              )
            )
          )
        })
        .catch(error => {
          Raven.captureException(error)
          return Observable.of({
            type: actions.USER_REMOVED_ASSET_FROM_LIST_FAILED,
            payload: error
          })
        })
    })

export default removeAssetFromWatchlist
