import GoogleAnalytics from 'react-ga'
import Raven from 'raven-js'
import {
  FollowProjectGQL,
  UnfollowProjectGQL,
  followedProjectsGQL
} from './../pages/Detailed/DetailedGQL'

const followProjectHelper = ({actionType, projectId}) => ({
  variables: {projectId: Number(projectId)},
  optimisticResponse: {
    __typename: 'Mutation',
    [actionType]: {
      __typename: 'Project',
      id: projectId
    }
  },
  update: (proxy) => {
    let data = proxy.readQuery({ query: followedProjectsGQL })
    const newFollowedProjects = data.followedProjects ? [...data.followedProjects] : []
    if (actionType === 'followProject') {
      newFollowedProjects.push({
        id: projectId,
        __typename: 'Project'
      })
      data.followedProjects = newFollowedProjects
    } else if (actionType === 'unfollowProject') {
      data.followedProjects = newFollowedProjects.filter(current => current.id !== projectId)
    }
    proxy.writeQuery({ query: followedProjectsGQL, data })
  }
})

const handleFollow = (action$, store, { client }) =>
  action$.ofType('TOGGLE_FOLLOW')
    .switchMap((action) => {
      const { actionType } = action.payload
      const mutation = actionType === 'followProject' ? FollowProjectGQL : UnfollowProjectGQL
      return client.mutate({
        mutation,
        ...followProjectHelper(action.payload)
      })
      .then(() => {
        GoogleAnalytics.event({
          category: 'Interactions',
          action: `User follow the project ${action.payload.projectId}`
        })
        return { type: 'TOGGLE_FOLLOW_SUCCESS' }
      })
      .catch(error => {
        Raven.captureException(error)
        return { type: 'TOGGLE_FOLLOW_FAILED' }
      })
    })

export default handleFollow
