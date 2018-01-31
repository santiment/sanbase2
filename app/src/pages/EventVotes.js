import React, { Fragment } from 'react'
import debounce from 'lodash.debounce'
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
import PostsList from './../components/PostsList'
import { simpleSort } from './../utils/sortMethods'
import { Button, Header, Icon, Modal, Message } from 'semantic-ui-react'
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
  Posts,
  votePost,
  unvotePost,
  location,
  history,
  match,
  user,
  toggleLoginRequest,
  isToggledLoginRequest
}) => {
  return ([
    <Fragment key='modal-login-request'>
      {isToggledLoginRequest &&
        <ModalRequestLogin
          toggleLoginRequest={toggleLoginRequest}
          history={history} />}
    </Fragment>,
    <div className='page event-votes' key='page-event-votes'>
      {location.state && location.state.postCreated &&
        <Message positive>
          <Message.Header>👏👏👏 Insight was created</Message.Header>
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
              to={'/events/votes'}>
              POPULAR
            </NavLink>
            <NavLink
              className='event-votes-navigation__link'
              activeClassName='event-votes-navigation__link--active'
              exact
              to={'/events/votes/newest'}>
              NEWEST
            </NavLink>
          </div>
          {user.token
            ? <NavLink
              className='event-votes-navigation__add-link'
              to={'/events/votes/new'}>
              Add new insight
            </NavLink>
            : <a
              onClick={() => toggleLoginRequest(!isToggledLoginRequest)}
              className='event-votes-navigation__add-link'>
                Add new insight
              </a>}
        </div>
        <PostsList {...Posts}
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
        />
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

const currentPollGQL = gql`{
  currentPoll {
    endAt
    posts {
      id
      title
      approvedAt
      votedAt
      link
      totalSanVotes
      user {
        username
      }
    }
    startAt
  }
}`

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
      new Date(postA.approvedAt).getTime(),
      new Date(postB.approvedAt).getTime()
    )
  )
}

const mapDataToProps = props => {
  const { Poll, ownProps } = props
  const filter = ownProps.match.params.filter || 'popular'
  const posts = ((posts = []) => {
    const normalizedPosts = posts.filter(post => post.approvedAt)
    .map(post => {
      return {totalSanVotes: post.totalSanVotes || 0, ...post}
    })
    if (filter === 'popular') {
      return sortByPopular(normalizedPosts)
    }
    return sortByNewest(normalizedPosts)
  })(Poll.currentPoll && Poll.currentPoll.posts)
  return {
    Posts: {
      ...Poll,
      loading: Poll.loading,
      isEmpty: Poll.currentPoll &&
        Poll.currentPoll.posts &&
        Poll.currentPoll.posts.length === 0,
      isError: !!Poll.error || false,
      errorMessage: Poll.error ? Poll.error.message : '',
      posts
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
  graphql(currentPollGQL, {
    name: 'Poll',
    props: mapDataToProps,
    options: { pollInterval: POLLING_INTERVAL }
  }),
  graphql(votePostGQL, {
    name: 'votePost',
    options: { fetchPolicy: 'network-only' }
  }),
  graphql(unvotePostGQL, {
    name: 'unvotePost',
    options: { fetchPolicy: 'network-only' }
  }),
  pure
)

export default enhance(EventVotes)
