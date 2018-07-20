import GoogleAnalytics from 'react-ga'
import Raven from 'raven-js'
import { Observable } from 'rxjs'
import { showNotification } from './../actions/rootActions'
import {
  FollowProjectGQL,
  UnfollowProjectGQL,
  followedProjectsGQL
} from './../pages/Detailed/DetailedGQL'

const followProjectHelper = ({ actionType, projectId }) => ({
  variables: { projectId: Number(projectId) },
  optimisticResponse: {
    __typename: 'Mutation',
    [actionType]: {
      __typename: 'Project',
      id: projectId
    }
  },
  update: proxy => {
    let data = proxy.readQuery({ query: followedProjectsGQL })
    const newFollowedProjects = data.followedProjects
      ? [...data.followedProjects]
      : []
    if (actionType === 'followProject') {
      newFollowedProjects.push({
        id: projectId,
        __typename: 'Project'
      })
      data.followedProjects = newFollowedProjects
    } else if (actionType === 'unfollowProject') {
      data.followedProjects = newFollowedProjects.filter(
        current => current.id !== projectId
      )
    }
    proxy.writeQuery({ query: followedProjectsGQL, data })
  }
})

const notificationMsg = actionType =>
  actionType === 'followProject'
    ? 'You followed this project'
    : 'You unfollowed this project'

const handleFollow = (action$, store, { client }) =>
  action$.ofType('TOGGLE_FOLLOW').switchMap(action => {
    const { actionType } = action.payload
    const mutation =
      actionType === 'followProject' ? FollowProjectGQL : UnfollowProjectGQL
    const mutationPromise = client.mutate({
      mutation,
      ...followProjectHelper(action.payload)
    })
    return Observable.from(mutationPromise)
      .mergeMap(() => {
        GoogleAnalytics.event({
          category: 'Interactions',
          action: `User follow the project ${action.payload.projectId}`
        })
        return Observable.merge(
          Observable.of({ type: 'TOGGLE_FOLLOW_SUCCESS' }),
          Observable.of(showNotification(notificationMsg(actionType)))
        )
      })
      .catch(error => {
        Raven.captureException(error)
        return Observable.of({ type: 'TOGGLE_FOLLOW_FAILED', payload: error })
      })
  })

export default handleFollow
