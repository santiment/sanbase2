import React from 'react'
import {
  compose,
  pure
} from 'recompose'
import { graphql } from 'react-apollo'
import gql from 'graphql-tag'
import { NavLink } from 'react-router-dom'
import Panel from './../components/Panel'
import PostsList from './../components/PostsList'
import { Icon, Message } from 'semantic-ui-react'
import './EventVotes.css'

const EventVotes = ({
  Posts,
  location
}) => {
  return (
    <div className='page event-votes'>
      {location.state && location.state.postCreated &&
        <Message positive>
          <Message.Header>Post created</Message.Header>
          <p>We need some time to approve your insight.</p>
        </Message>}
      <Panel>
        <div className='event-votes-header'>
          <span>Insights</span>
          <NavLink
            className='event-votes-navigation__add-link'
            to={'/events/votes/new'}>
            <Icon name='als' /> Add new insight
          </NavLink>
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
        </div>
        <PostsList {...Posts} />
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
      link
      user {
        username
      }
      totalSanVotes
    }
    startAt
  }
}`

const mapDataToProps = ({Poll}) => {
  return {
    Posts: {
      loading: Poll.loading,
      isEmpty: Poll.currentPoll &&
        Poll.currentPoll.posts &&
        Poll.currentPoll.posts.length === 0,
      isError: !!Poll.error || false,
      errorMessage: Poll.error ? Poll.error.message : '',
      posts: (Poll.currentPoll && Poll.currentPoll.posts) || []
    }
  }
}

const enhance = compose(
  graphql(currentPollGQL, {
    name: 'Poll',
    props: mapDataToProps
  }),
  pure
)

export default enhance(EventVotes)
