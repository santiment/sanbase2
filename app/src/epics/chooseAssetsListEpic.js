import Raven from 'raven-js'
import gql from 'graphql-tag'
import { Observable } from 'rxjs'
import { showNotification } from './../actions/rootActions'
import { projectBySlugGQL } from './../pages/Projects/allProjectsGQL'
import * as actions from './../actions/types'

const chooseAssetsListEpic = action$ =>
  action$.ofType(actions.USER_CHOOSE_ASSET_LIST).map(action => {
    const { id, name } = action.payload
    return {
      type: '@@router/LOCATION_CHANGE',
      payload: {
        pathname: '/assets/list',
        search: `?name=${name}@${id}`,
        hash: ''
      }
    }
  })

export default chooseAssetsListEpic
