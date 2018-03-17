import React, { Fragment } from 'react'
import debounce from 'lodash.debounce'
import { Helmet } from 'react-helmet'
import Raven from 'raven-js'
import {
  compose,
  withState,
  pure
} from 'recompose'
import { connect } from 'react-redux'
import { graphql } from 'react-apollo'
import gql from 'graphql-tag'
import { NavLink } from 'react-router-dom'
import Panel from './../components/Panel'
import PostList from './../components/PostList'
import { simpleSort } from './../utils/sortMethods'
import { Button, Header, Icon, Modal, Message } from 'semantic-ui-react'
import ModalConfirmDeletePost from './Insights/ConfirmDeletePostModal'
import currentPollGQL from './Insights/currentPollGQL'
import './EventVotes.css'

const POLLING_INTERVAL = 10000

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
    const data = proxy.readQuery({ query: currentPollGQL })
    const newPosts = [...data.currentPoll.posts]
    const postIndex = newPosts.findIndex(post => post.id === changedPost.id)
    newPosts[postIndex].votedAt = action === 'vote' ? new Date() : null
    data.currentPoll.posts = newPosts
    proxy.writeQuery({ query: currentPollGQL, data })
  }
})

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
  toggleLoginRequest,
  isToggledLoginRequest,
  toggleDeletePostRequest,
  isToggledDeletePostRequest,
  setDeletePostId,
  deletePostId = undefined
}) => {
  const showedMyPosts = match.path.split('/')[2] === 'my' && Posts.hasUserInsights

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
    <div className='page event-votes' key='page-event-votes'>
      <Helmet>
        <title>SANbase: Insights</title>
      </Helmet>
      {location.state && location.state.postCreated &&
        <Message positive>
          <Message.Header>
            <span role='img' aria-label='Clap'>👏</span>
            <span role='img' aria-label='Clap'>👏</span>
            <span role='img' aria-label='Clap'>👏</span>
            Insight was created
          </Message.Header>
          <p>We need some time to approve your insight...</p>
        </Message>}
      <Panel>
        <div className='panel-header'>
          Insights
        </div>
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
            {Posts.hasUserInsights &&
              <Fragment>
                <NavLink
                  className='event-votes-navigation__add-link'
                  to={'/insights/my'}>
                  My Insights
                </NavLink>
                &nbsp;|&nbsp;
              </Fragment>}
            {user.token
              ? <NavLink
                className='event-votes-navigation__add-link'
                to={'/insights/new'}>
                Add new insight
              </NavLink>
              : <a
                onClick={() => toggleLoginRequest(!isToggledLoginRequest)}
                className='event-votes-navigation__add-link'>
                  Add new insight
                </a>}
          </div>
        </div>
        {Posts.isEmpty && !showedMyPosts
          ? <Message><h2>We don't have any insights yet.</h2></Message>
          : <PostList {...Posts}
            posts={showedMyPosts ? Posts.userPosts : Posts.filteredPosts}
            userId={showedMyPosts ? user.data.id : undefined}
            deletePost={postId => {
              setDeletePostId(postId)
              toggleDeletePostRequest(true)
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
    </div>
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
  const { Poll, ownProps } = props
  const filter = ownProps.match.path.split('/')[2] || 'popular'
  const posts = (Poll.currentPoll || {}).posts || []
  let filteredPosts = posts
    // TODO: We should return this filter in the near future
    // .filter(post => post.state === 'approved')
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

  if (Poll.error) {
    throw new Error(Poll.error)
  }

  return {
    Posts: {
      posts,
      filteredPosts,
      userPosts,
      refetch: Poll.refetch,
      loading: Poll.loading,
      isEmpty: Poll.currentPoll &&
        filteredPosts &&
        filteredPosts.length === 0,
      hasUserInsights: userPosts.length > 0,
      isError: !!Poll.error || false,
      errorMessage: Poll.error ? Poll.error.message : ''
    }
  }
}

const mapStateToProps = state => {
  return {
    user: state.user
  }
}

const enhance = compose(
  connect(
    mapStateToProps
  ),
  withState('isToggledLoginRequest', 'toggleLoginRequest', false),
  withState('isToggledDeletePostRequest', 'toggleDeletePostRequest', false),
  withState('deletePostId', 'setDeletePostId', undefined),
  graphql(currentPollGQL, {
    name: 'Poll',
    props: mapDataToProps,
    options: { pollInterval: POLLING_INTERVAL }
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
