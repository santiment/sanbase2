import React, { Fragment } from 'react'
import debounce from 'lodash.debounce'
import moment from 'moment'
import * as qs from 'query-string'
import Raven from 'raven-js'
import { compose, withState } from 'recompose'
import { connect } from 'react-redux'
import { Button, Header, Icon, Modal, Message } from 'semantic-ui-react'
import { graphql } from 'react-apollo'
import gql from 'graphql-tag'
import { NavLink, Redirect } from 'react-router-dom'
import PostList from './../components/PostList'
import { simpleSort } from './../utils/sortMethods'
import ModalConfirmDeletePost from './Insights/ConfirmDeletePostModal'
import ModalConfirmPublishPost from './Insights/ConfirmPublishPostModal'
import { allInsightsPublicGQL, allInsightsGQL } from './Insights/currentPollGQL'
import InsightsLayout from './Insights/InsightsLayout'
import { getBalance, checkIsLoggedIn } from './UserSelectors'
import './InsightsPage.css'

const POLLING_INTERVAL = 5000

export const voteMutationHelper = ({postId, action = 'vote'}) => ({
  variables: {postId: parseInt(postId, 10)},
  optimisticResponse: {
    __typename: 'Mutation',
    [action]: {
      __typename: 'Post',
      id: postId
    }
  },
  update: (proxy, { data: { vote, unvote } }) => {
    const changedPost = action === 'vote' ? vote : unvote
    const data = proxy.readQuery({ query: allInsightsGQL })
    const newPosts = data.allInsights ? [...data.allInsights] : []
    const postIndex = newPosts.findIndex(post => post.id === changedPost.id)
    newPosts[postIndex].votedAt = action === 'vote' ? new Date() : null
    data.allInsights = newPosts
    proxy.writeQuery({ query: allInsightsGQL, data })
  }
})

const formatDay = timestamp => {
  if (moment.unix(timestamp).isSame(moment(), 'day')) {
    return 'Today'
  }
  return moment.unix(timestamp).format('MMM Do YYYY')
}

const InsightsPage = ({
  Posts = {
    posts: [],
    loading: true,
    isEmpty: false,
    hasUserInsights: false,
    isError: false,
    errorMessage: '',
    refetch: null
  },
  votePost,
  unvotePost,
  location,
  history,
  match,
  user,
  isLoggedIn,
  balance,
  toggleDeletePostRequest,
  isToggledDeletePostRequest,
  togglePublishPostRequest,
  isToggledPublishPostRequest,
  setDeletePostId,
  deletePostId = undefined,
  setPublishInsightId,
  publishInsightId = undefined,
  isOpenedLoginRequestModal,
  loginModalRequest
}) => {
  const showedMyPosts = match.path.split('/')[2] === 'my' && Posts.hasUserInsights
  if (match.path.split('/')[2] === 'my' && !Posts.hasUserInsights) {
    return <Redirect to='/insights' />
  }
  return ([
    <Fragment key='modal-login-request'>
      {isOpenedLoginRequestModal &&
        <ModalRequestLogin
          toggleLoginRequest={loginModalRequest}
          history={history} />}
    </Fragment>,
    <Fragment key='modal-delete-post-request'>
      {isToggledDeletePostRequest &&
        <ModalConfirmDeletePost
          deletePostId={deletePostId}
          toggleForm={() => {
            if (isToggledDeletePostRequest) {
              setDeletePostId(undefined)
            }
            toggleDeletePostRequest(!isToggledDeletePostRequest)
          }} />}
    </Fragment>,
    <Fragment key='modal-publish-post-request'>
      {isToggledPublishPostRequest &&
        <ModalConfirmPublishPost
          publishInsightId={publishInsightId}
          toggleForm={() => {
            if (isToggledPublishPostRequest) {
              setPublishInsightId(undefined)
            }
            togglePublishPostRequest(!isToggledPublishPostRequest)
          }} />}
    </Fragment>,
    <Fragment key='page-event-votes'>
      <InsightsLayout isLogin={isLoggedIn}>
        <div className='insight-list'>
          {Posts.isEmpty && !showedMyPosts
            ? <Message><h2>We don't have any insights yet.</h2></Message>
            : Object.keys(Posts.posts).sort().reverse().map((key, index) => (
              <div key={key} className='posts-by-day'>
                <div className='posts-by-day-header'>
                  <span className='represent-day'>{formatDay(key)}</span>
                  {index === 0 &&
                    <div className='event-votes-control'>
                      <div className='event-votes-navigation'>
                        <NavLink
                          className='event-votes-navigation__link'
                          activeClassName='event-votes-navigation__link--active'
                          exact
                          to={'?sort=popular'}>
                          POPULAR
                        </NavLink>
                        <NavLink
                          className='event-votes-navigation__link'
                          activeClassName='event-votes-navigation__link--active'
                          exact
                          to={'?sort=newest'}>
                          NEWEST
                        </NavLink>
                      </div>
                    </div>}
                </div>
                <PostList {...Posts}
                  posts={Posts.posts[key]}
                  userId={showedMyPosts ? user.data.id : undefined}
                  balance={balance}
                  gotoInsight={id => {
                    if (!user.token) {
                      loginModalRequest(true)
                    } else {
                      history.push(`/insights/${id}`)
                    }
                  }}
                  deletePost={postId => {
                    setDeletePostId(postId)
                    toggleDeletePostRequest(true)
                  }}
                  publishPost={postId => {
                    setPublishInsightId(postId)
                    togglePublishPostRequest(true)
                  }}
                  votePost={debounce(postId => {
                    user.token
                      ? votePost(voteMutationHelper({postId, action: 'vote'}))
                      .then(data => Posts.refetch())
                      .catch(e => Raven.captureException(e))
                      : loginModalRequest()
                  }, 100)}
                  unvotePost={debounce(postId => {
                    user.token
                      ? unvotePost(voteMutationHelper({postId, action: 'unvote'}))
                      .then(data => Posts.refetch())
                      .catch(e => Raven.captureException(e))
                      : loginModalRequest()
                  }, 100)}
                />
              </div>
            ))}
        </div>
      </InsightsLayout>
    </Fragment>
  ])
}

const ModalRequestLogin = ({history, toggleLoginRequest}) => (
  <Modal defaultOpen onClose={() => toggleLoginRequest(false)} closeIcon>
    <Header content='Create an account to get your Sanbase experience.' />
    <Modal.Content>
      <p>By having a Sanbase account, you can see more data and insights about crypto projects.
      You can vote and comment on all you favorite insights and more.</p>
    </Modal.Content>
    <Modal.Actions>
      <Button
        onClick={() =>
          history.push(`/login?redirect_to=${history.location.pathname}`)}
        color='green'>
        <Icon name='checkmark' /> Login or Sign up
      </Button>
    </Modal.Actions>
  </Modal>
)

export const votePostGQL = gql`
  mutation vote($postId: Int!){
    vote(postId: $postId) {
      id
    }
  }
`

export const unvotePostGQL = gql`
  mutation unvote($postId: Int!){
    unvote(postId: $postId) {
      id
    }
  }
`

export const sortByPopular = posts => {
  return posts.sort((postA, postB) =>
    simpleSort(postA.votes.totalSanVotes, postB.votes.totalSanVotes)
  )
}

export const sortByNewest = posts => {
  return posts.sort((postA, postB) =>
    simpleSort(
      new Date(postA.createdAt).getTime(),
      new Date(postB.createdAt).getTime()
    )
  )
}

const mapDataToProps = props => {
  const { Insights, ownProps } = props
  const filter = ownProps.match.path.split('/')[2] || 'all'
  const qsData = qs.parse(ownProps.location.search)
  const sort = qsData['sort'] ? qsData.sort : 'popular'
  const posts = Insights.allInsights || []
  let normalizedPosts = posts
    .map(post => {
      return {
        votes: {
          totalSanVotes: parseFloat(post.votes.totalSanVotes) || 0
        },
        ...post}
    })

  const filteredByPublished = posts => posts.filter(post => post.readyState ? post.readyState === 'published' : true)
  const filteredBySelfUser = posts => posts.filter(post => post.user.id === ownProps.user.data.id)
  const hasUserInsights = filteredBySelfUser(normalizedPosts).length > 0
  const filteredByUserID = posts => posts.filter(post => post.user.id === ownProps.match.params.userId)

  const searchedTag = ownProps.match.params.tagName && ownProps.match.params.tagName.toLowerCase() // This optimize calculations inside filter func
  const filteredByTagPosts = posts => posts.filter(post => post.tags.some(({ name }) => name.toLowerCase() === searchedTag))

  const postsByDay = normalizedPosts.reduce((acc, post) => {
    const day = moment(post.createdAt).endOf('day').unix()
    if (!acc[`${day}`]) {
      acc[`${day}`] = []
    }
    acc[`${day}`].push(post)
    return acc
  }, {})

  const reduceAllKeys = postsByDay => filterFn => Object.keys(postsByDay).reduce((acc, key) => {
    const filtered = filterFn(postsByDay[key])
    if (filtered.length > 0) {
      acc[key] = filtered
    }
    return acc
  }, {})

  const applyFilter = posts => {
    if (filter === 'users') {
      return reduceAllKeys(posts)(
        compose(
          filteredByPublished,
          filteredByUserID,
          filteredByTagPosts
        )
      )
    } else if (filter === 'my') {
      return reduceAllKeys(posts)(filteredBySelfUser)
    } else if (filter === 'tags') {
      return reduceAllKeys(posts)(filteredByTagPosts)
    }
    return reduceAllKeys(posts)(filteredByPublished)
  }

  const applySort = posts => {
    if (sort === 'newest') {
      return reduceAllKeys(posts)(sortByNewest)
    }
    return reduceAllKeys(posts)(sortByPopular)
  }

  const visiblePosts = compose(
    applyFilter,
    applySort
  )(postsByDay)

  return {
    Posts: {
      posts: visiblePosts,
      refetch: Insights.refetch,
      updateQuery: Insights.updateQuery,
      loading: Insights.loading,
      isEmpty: Insights.currentPoll &&
        visiblePosts &&
        Object.keys(visiblePosts).length === 0,
      hasUserInsights,
      isError: !!Insights.error || false,
      errorMessage: Insights.error ? Insights.error.message : ''
    }
  }
}

const mapStateToProps = state => {
  return {
    user: state.user,
    isLoggedIn: checkIsLoggedIn(state),
    balance: getBalance(state),
    isOpenedLoginRequestModal: state.insightsPageUi.isOpenedLoginRequestModal
  }
}

const mapDispatchToProps = dispatch => {
  return {
    loginModalRequest: () => {
      dispatch({
        type: 'TOGGLE_LOGIN_REQUEST_MODAL'
      })
    }
  }
}

const enhance = compose(
  connect(
    mapStateToProps,
    mapDispatchToProps
  ),
  withState('isToggledDeletePostRequest', 'toggleDeletePostRequest', false),
  withState('isToggledPublishPostRequest', 'togglePublishPostRequest', false),
  withState('deletePostId', 'setDeletePostId', undefined),
  withState('publishInsightId', 'setPublishInsightId', undefined),
  graphql(allInsightsPublicGQL, {
    name: 'Insights',
    props: mapDataToProps,
    options: ({isLoggedIn}) => ({
      skip: isLoggedIn,
      pollInterval: POLLING_INTERVAL
    })
  }),
  graphql(allInsightsGQL, {
    name: 'Insights',
    props: mapDataToProps,
    options: ({isLoggedIn}) => ({
      skip: !isLoggedIn,
      pollInterval: POLLING_INTERVAL
    })
  }),
  graphql(votePostGQL, {
    name: 'votePost'
  }),
  graphql(unvotePostGQL, {
    name: 'unvotePost'
  })
)

export default enhance(InsightsPage)
