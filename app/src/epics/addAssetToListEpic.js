import Raven from 'raven-js'
import gql from 'graphql-tag'
import { Observable } from 'rxjs'
import { showNotification } from './../actions/rootActions'
import { AssetsListGQL } from './../components/AssetsListPopup/AssetsListGQL'
import * as actions from './../actions/types'

const updateUserListGQL = gql`
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
    }
  }
`

const addAssetToListEpic = (action$, store, { client }) =>
  action$
    .ofType(actions.USER_ADD_ASSET_TO_LIST)
    .debounceTime(200)
    .mergeMap(action => {
      const { projectId, assetsListId } = action.payload
      const mutationPromise = client.mutate({
        mutation: updateUserListGQL,
        variables: {
          id: +assetsListId,
          listItems: [{ project_id: +projectId }]
        }
      })
      return Observable.from(mutationPromise)
        .mergeMap(({ data }) => {
          return Observable.merge(
            Observable.of({
              type: actions.USER_ADD_ASSET_TO_LIST_SUCCESS
            }),
            Observable.of(showNotification('Added this asset to the list'))
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
