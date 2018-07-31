import Raven from 'raven-js'
import { Observable } from 'rxjs'
import { showNotification } from './../actions/rootActions'
import { AssetsListGQL } from './../components/AssetsListPopup/AssetsListGQL'
import { updateUserListGQL } from './addAssetToListEpic'
import * as actions from './../actions/types'

const removeAssetFromListEpic = (action$, store, { client }) =>
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
          const data = store.readQuery({ query: AssetsListGQL })
          const index = data.fetchUserLists.findIndex(
            list => list.id === updateUserList.id
          )
          data.fetchUserLists[index].listItems = newListItems
          store.writeQuery({ query: AssetsListGQL, data })
        }
      })
      return Observable.from(mutationPromise)
        .mergeMap(({ data }) => {
          return Observable.merge(
            Observable.of({
              type: actions.USER_REMOVED_ASSET_FROM_LIST_SUCCESS
            }),
            Observable.of(showNotification('Removed this asset from the list'))
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

export default removeAssetFromListEpic
