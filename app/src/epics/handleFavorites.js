import { followedProjectsGQL } from './../pages/Login/LoginGQL'
import { FollowProjectGQL, UnfollowProjectGQL } from './../pages/Detailed/DetailedGQL'

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

const handleFavorites = (action$, store, { client }) =>
  action$.ofType('TOGGLE_FAVORITE')
    .map((action) => {
      const { actionType } = action.payload
      const mutation = actionType === 'followProject' ? FollowProjectGQL : UnfollowProjectGQL
      client.mutate({
        mutation,
        ...followProjectHelper(action.payload)
      })
      .catch(e => console.log(e))
      return { type: 'PONG' }
    })

export default handleFavorites
