import React, { Fragment } from 'react'
import debounce from 'lodash.debounce'
import Raven from 'raven-js'
import {
  compose,
  withState,
  pure
} from 'recompose'
import { connect } from 'react-redux'
import { Button, Header, Icon, Modal, Message } from 'semantic-ui-react'
import { graphql } from 'react-apollo'
import gql from 'graphql-tag'
import { NavLink, Redirect } from 'react-router-dom'
import Panel from './../components/Panel'
import PostList from './../components/PostList'
import { simpleSort } from './../utils/sortMethods'
import ModalConfirmDeletePost from './Insights/ConfirmDeletePostModal'
import ModalConfirmPublishPost from './Insights/ConfirmPublishPostModal'
import { allInsightsPublicGQL, allInsightsGQL } from './Insights/currentPollGQL'
import InsightsLayout from './Insights/InsightsLayout'
import './EventVotes.css'

const POLLING_INTERVAL = 5000

const voteMutationHelper = ({postId, action = 'vote'}) => ({
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
    const newPosts = [...data.allInsights]
    const postIndex = newPosts.findIndex(post => post.id === changedPost.id)
    newPosts[postIndex].votedAt = action === 'vote' ? new Date() : null
    data.allInsights = newPosts
    proxy.writeQuery({ query: allInsightsGQL, data })
  }
})

const getPosts = (match, history, Posts) => {
  const showedUserByIdPosts = match.path.split('/')[2] === 'users'
  if (match.path.split('/')[2] === 'my') {
    if (Posts.hasUserInsights) {
      return Posts.userPosts
    }
    return []
  }
  if (showedUserByIdPosts) {
    return Posts.postsByUserId
  }
  return Posts.filteredPosts
}

const EventVotes = ({
  Posts = {
    posts: [],
    filteredPosts: [],
    userPosts: [],
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
  balance,
  toggleLoginRequest,
  isToggledLoginRequest,
  toggleDeletePostRequest,
  isToggledDeletePostRequest,
  togglePublishPostRequest,
  isToggledPublishPostRequest,
  setDeletePostId,
  deletePostId = undefined,
  setPublishInsightId,
  publishInsightId = undefined
}) => {
  const showedMyPosts = match.path.split('/')[2] === 'my' && Posts.hasUserInsights
  if (match.path.split('/')[2] === 'my' && !Posts.hasUserInsights) {
    return <Redirect to='/insights/newest' />
  }
  return ([
    <Fragment key='modal-login-request'>
      {isToggledLoginRequest &&
        <ModalRequestLogin
          toggleLoginRequest={toggleLoginRequest}
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
      <InsightsLayout isLogin={!!user.token}>
        <Panel className='event-votes-content'>
          <div className='event-votes-control'>
            <div className='event-votes-navigation'>
              <NavLink
                className='event-votes-navigation__link'
                activeClassName='event-votes-navigation__link--active'
                exact
                to={'/insights'}>
                POPULAR
              </NavLink>
              <NavLink
                className='event-votes-navigation__link'
                activeClassName='event-votes-navigation__link--active'
                exact
                to={'/insights/newest'}>
                NEWEST
              </NavLink>
            </div>
            <div>
              {user.token
                ? <NavLink
                  className='event-votes-navigation__add-link'
                  to={'/insights/new'}>
                  <Icon name='plus' /> New insight
                </NavLink>
                : <a
                  onClick={() => toggleLoginRequest(!isToggledLoginRequest)}
                  className='event-votes-navigation__add-link'>
                  <Icon name='plus' /> New insight
                  </a>}
            </div>
          </div>
          {Posts.isEmpty && !showedMyPosts
            ? <Message><h2>We don't have any insights yet.</h2></Message>
            : <PostList {...Posts}
              posts={getPosts(match, history, Posts)}
              userId={showedMyPosts ? user.data.id : undefined}
              balance={balance}
              gotoInsight={id => {
                if (!user.token) {
                  toggleLoginRequest(true)
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
                  : toggleLoginRequest(!isToggledLoginRequest)
              }, 100)}
              unvotePost={debounce(postId => {
                user.token
                  ? unvotePost(voteMutationHelper({postId, action: 'unvote'}))
                  .then(data => Posts.refetch())
                  .catch(e => Raven.captureException(e))
                  : toggleLoginRequest(!isToggledLoginRequest)
              }, 100)}
          />}
        </Panel>
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

const votePostGQL = gql`
  mutation vote($postId: Int!){
    vote(postId: $postId) {
      id
    }
  }
`

const unvotePostGQL = gql`
  mutation unvote($postId: Int!){
    unvote(postId: $postId) {
      id
    }
  }
`

export const sortByPopular = posts => {
  return posts.sort((postA, postB) =>
    simpleSort(postA.totalSanVotes, postB.totalSanVotes)
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
  const filter = ownProps.match.path.split('/')[2] || 'popular'
  const posts = Insights.allInsights || []
  let filteredPosts = posts
    .filter(post => post.readyState ? post.readyState === 'published' : true)
    .map(post => {
      return {
        totalSanVotes: parseFloat(post.totalSanVotes) || 0,
        ...post}
    })
  filteredPosts = sortByNewest(filteredPosts)
  if (filter === 'popular') {
    filteredPosts = sortByPopular(filteredPosts)
  }

  const userPosts = sortByNewest(
    posts.filter(post => post.user.id === ownProps.user.data.id)
  )

  const postsByUserId = filter === 'users'
    ? sortByNewest(
      posts.filter(post => post.user.id === ownProps.match.params.userId)
    )
    : []

  if (Insights.error) {
    throw new Error(Insights.error)
  }

  return {
    Posts: {
      posts,
      filteredPosts,
      userPosts,
      postsByUserId,
      refetch: Insights.refetch,
      updateQuery: Insights.updateQuery,
      loading: Insights.loading,
      isEmpty: Insights.currentPoll &&
        filteredPosts &&
        filteredPosts.length === 0,
      hasUserInsights: userPosts.length > 0,
      isError: !!Insights.error || false,
      errorMessage: Insights.error ? Insights.error.message : ''
    }
  }
}

const mapStateToProps = state => {
  const getBalance = (state) => {
    const ethAccounts = state.user.data.ethAccounts
    if (ethAccounts) {
      return state.user.data.ethAccounts.length > 0
        ? state.user.data.ethAccounts[0].sanBalance
        : 0
    }
    return 0
  }
  return {
    user: state.user,
    balance: getBalance(state)
  }
}

const enhance = compose(
  connect(
    mapStateToProps
  ),
  withState('isToggledLoginRequest', 'toggleLoginRequest', false),
  withState('isToggledDeletePostRequest', 'toggleDeletePostRequest', false),
  withState('isToggledPublishPostRequest', 'togglePublishPostRequest', false),
  withState('deletePostId', 'setDeletePostId', undefined),
  withState('publishInsightId', 'setPublishInsightId', undefined),
  graphql(allInsightsPublicGQL, {
    name: 'Insights',
    props: mapDataToProps,
    options: ({user}) => ({
      skip: user.token,
      pollInterval: POLLING_INTERVAL
    })
  }),
  graphql(allInsightsGQL, {
    name: 'Insights',
    props: mapDataToProps,
    options: ({user}) => ({
      skip: !user.token,
      pollInterval: POLLING_INTERVAL
    })
  }),
  graphql(votePostGQL, {
    name: 'votePost'
  }),
  graphql(unvotePostGQL, {
    name: 'unvotePost'
  }),
  pure
)

export default enhance(EventVotes)
