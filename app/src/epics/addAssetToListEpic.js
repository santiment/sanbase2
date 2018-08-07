import Raven from 'raven-js'
import gql from 'graphql-tag'
import { Observable } from 'rxjs'
import { showNotification } from './../actions/rootActions'
import { AssetsListGQL } from './../components/AssetsListPopup/AssetsListGQL'
import * as actions from './../actions/types'

export const updateUserListGQL = gql`
  mutation updateUserList(
    $id: Int!
    $isPublic: Boolean
    $name: String
    $color: ColorEnum
    $listItems: [InputListItem]
  ) {
    updateUserList(
      id: $id
      isPublic: $isPublic
      name: $name
      color: $color
      listItems: $listItems
    ) {
      id
      listItems {
        project {
          id
        }
      }
      isPublic
      name
      color
      insertedAt
      updatedAt
    }
  }
`

const addAssetToListEpic = (action$, store, { client }) =>
  action$
    .ofType(actions.USER_ADD_ASSET_TO_LIST)
    .debounceTime(200)
    .mergeMap(action => {
      const { assetsListId, listItems = [], projectId } = action.payload
      const normalizedList = listItems.map(val => {
        return { project_id: +val.project.id }
      })
      const newListItems = [...normalizedList, { project_id: +projectId }]
      const mutationPromise = client.mutate({
        mutation: updateUserListGQL,
        variables: {
          id: +assetsListId,
          listItems: newListItems
        },
        update: (store, { data: { updateUserList } }) => {
          const data = store.readQuery({ query: AssetsListGQL })
          const index = data.fetchUserLists.findIndex(
            list => list.id === updateUserList.id
          )
          data.fetchUserLists[index] = updateUserList
          store.writeQuery({ query: AssetsListGQL, data })
        }
      })
      return Observable.from(mutationPromise)
        .mergeMap(({ data }) => {
          const assetSlug = action.payload.slug
          const watchlistName = data.updateUserList.name
          return Observable.merge(
            Observable.of({
              type: actions.USER_ADD_ASSET_TO_LIST_SUCCESS
            }),
            Observable.of(
              showNotification(
                `Added "${assetSlug}" to the list "${watchlistName}"`
              )
            )
          )
        })
        .catch(error => {
          Raven.captureException(error)
          return Observable.of({
            type: actions.USER_ADD_ASSET_TO_LIST_FAILED,
            payload: error
          })
        })
    })

export default addAssetToListEpic
