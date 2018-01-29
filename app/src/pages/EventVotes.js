import React from 'react'
import {
  compose,
  pure
} from 'recompose'
import { connect } from 'react-redux'
import { graphql } from 'react-apollo'
import gql from 'graphql-tag'
import { NavLink } from 'react-router-dom'
import Panel from './../components/Panel'
import PostsList from './../components/PostsList'
import { simpleSort } from './../utils/sortMethods'
import { Message } from 'semantic-ui-react'
import './EventVotes.css'

const EventVotes = ({
  Posts,
  votePost,
  unvotePost,
  location,
  match,
  user
}) => {
  return (
    <div className='page event-votes'>
      {location.state && location.state.postCreated &&
        <Message positive>
          <Message.Header>Insight created</Message.Header>
          <p>We need some time to approve your insight.</p>
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
          {user.token &&
            <NavLink
              className='event-votes-navigation__add-link'
              to={'/events/votes/new'}>
              Add new insight
            </NavLink>}
        </div>
        <PostsList {...Posts}
          votePost={postId => {
            votePost({
              variables: {postId: parseInt(postId)}
            })
            .then(data => Posts.refetch())
            .catch(e => console.log(e))
          }}
          unvotePost={postId => {
            unvotePost({
              variables: {postId: parseInt(postId)}
            })
            .then(data => Posts.refetch())
            .catch(e => console.log(e))
          }}
        />
      </Panel>
    </div>
  )
}

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
  graphql(currentPollGQL, {
    name: 'Poll',
    props: mapDataToProps,
    options: { pollInterval: 2000 }
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
