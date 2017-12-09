import Raven from 'raven-js'
import gql from 'graphql-tag'
import { Observable } from 'rxjs'
import { showNotification } from './../actions/rootActions'
import { WatchlistGQL } from './../components/WatchlistPopup/WatchlistGQL'
import * as actions from './../actions/types'

const createUserListGQL = gql`
  mutation createUserList(
    $color: ColorEnum
    $isPublic: Boolean
    $name: String!
  ) {
    createUserList(color: $color, isPublic: $isPublic, name: $name) {
      id
      name
      isPublic
      color
      insertedAt
      updatedAt
      listItems {
        project {
          id
        }
      }
    }
  }
`

const createWatchlistEpic = (action$, store, { client }) =>
  action$
    .ofType(actions.USER_ADD_NEW_ASSET_LIST)
    .debounceTime(200)
    .mergeMap(action => {
      const {
        name,
        color = 'NONE',
        isPublic = false,
        listItems = []
      } = action.payload
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
            name,
            listItems,
            insertedAt: new Date(),
            updatedAt: new Date()
          }
        },
        update: (store, { data: { createUserList } }) => {
          const data = store.readQuery({ query: WatchlistGQL })
          data.fetchUserLists.push(createUserList)
          store.writeQuery({ query: WatchlistGQL, data })
        }
      })
      return Observable.from(mutationPromise)
        .mergeMap(({ data }) => {
          return Observable.merge(
            Observable.of({
              type: actions.USER_ADD_NEW_ASSET_LIST_SUCCESS
            }),
            Observable.of(showNotification('Added new assets list'))
          )
        })
        .catch(error => {
          Raven.captureException(error)
          return Observable.of({
            type: actions.USER_ADD_NEW_ASSET_LIST_FAILED,
            payload: error
          })
        })
    })

export const createWatchlistSuccessEpic = (action$, store, { client }) =>
  action$
    .ofType(actions.USER_ADD_NEW_ASSET_LIST_SUCCESS)
    .delay(2000)
    .mapTo({ type: actions.USER_ADD_NEW_ASSET_LIST_CANCEL })

export default createWatchlistEpic
