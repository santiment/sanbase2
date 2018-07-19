import Raven from 'raven-js'
import gql from 'graphql-tag'
import { Observable } from 'rxjs'
import { showNotification } from './../actions/rootActions'
import { AssetsListGQL } from './../components/AssetsListPopup/AssetsListGQL'
import * as actions from './../actions/types'

const createUserListGQL = gql`
  mutation createUserList(
    $color: ColorEnum,
    $isPublic: Boolean,
    $name: String!
  ) {
    createUserList(
      color: $color,
      isPublic: $isPublic,
      name: $name
    ) {
     id,
     name,
     isPublic
    }
  }
`

const addNewAssetsListEpic = (action$, store, { client }) =>
  action$.ofType(actions.USER_ADD_NEW_ASSET_LIST)
    .switchMap(action => {
      const { name, color = 'NONE', isPublic = false } = action.payload
      const mutationPromise = client.mutate({
        mutation: createUserListGQL,
        variables: {
          name,
          isPublic,
          color
        },
        optimisticResponse: {
          __typename: 'Mutation',
          createUserList: {
            __typename: 'UserList',
            id: +new Date(),
            color,
            isPublic,
            name
          }
        },
        update: (proxy) => {
          let data = proxy.readQuery({ query: AssetsListGQL })
          const _userLists = data.fetchUserLists ? [...data.fetchUserLists] : []
          _userLists.push({
            id: +new Date(),
            color,
            name,
            isPublic,
            __typename: 'UserList'
          })
          data.fetchUserLists = _userLists
          proxy.writeQuery({ query: AssetsListGQL, data })
        }
      })
      return Observable.from(mutationPromise)
        .mergeMap(({ data }) => {
          console.log('success')
          return Observable.merge(
            Observable.of({
              type: actions.USER_ADD_NEW_ASSET_LIST_SUCCESS
            }),
            Observable.of(showNotification('Added new assets list'))
          )
        })
        .catch(error => {
          Raven.captureException(error)
          return Observable.of({ type: actions.USER_ADD_NEW_ASSET_LIST_FAILED, payload: error })
        })
    })


export const addNewSuccessEpic = (action$, store, { client }) =>
  action$.ofType(actions.USER_ADD_NEW_ASSET_LIST_SUCCESS)
  .delay(2000)
  .mapTo({type: actions.USER_ADD_NEW_ASSET_LIST_CANCEL})

export default addNewAssetsListEpic
