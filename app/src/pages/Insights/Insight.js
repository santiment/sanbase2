import React from 'react'
import {
  compose,
  pure
} from 'recompose'
import moment from 'moment'
import Panel from './../../components/Panel'
import gql from 'graphql-tag'
import { graphql } from 'react-apollo'
import './Insight.css'

const POLLING_INTERVAL = 100000

const Insight = ({
  Post = {
    loading: true,
    post: null
  }
}) => {
  const { post = {
    title: '',
    text: '',
    createdAt: null,
    username: null
  }, loading } = Post
  if (loading) {
    return (
      'Loading...'
    )
  }
  return (
    <div className='page insight'>
      <Panel>
        <h2>
          {post.title}
        </h2>
        <span style={{marginLeft: 2}}>
          by {post.username
            ? `${post.username}`
            : 'unknown author'}
        </span>
        &nbsp;&#8226;&nbsp;
        {post.createdAt &&
          <span>{moment(post.createdAt).format('MMM DD, YYYY')}</span>}
        <p>{post.text}</p>
      </Panel>
    </div>
  )
}

export const postGQL = gql`
  query postGQL($id: ID!) {
    post(
      id: $id,
    ){
      id
      title
      text
      shortDesc
      createdAt
      state
      user {
        username
      }
      votedAt
      totalSanVotes
      relatedProjects {
        ticker
      }
    }
  }
`

const enhance = compose(
  graphql(postGQL, {
    name: 'Post',
    options: ({match}) => ({
      skip: !match.params.insightId,
      errorPolicy: 'all',
      pollInterval: POLLING_INTERVAL,
      variables: {
        id: +match.params.insightId
      }
    })
  }),
  pure
)

export default enhance(Insight)
