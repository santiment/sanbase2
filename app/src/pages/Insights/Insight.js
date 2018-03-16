import React from 'react'
import {
  compose,
  pure
} from 'recompose'
import moment from 'moment'
import Panel from './../../components/Panel'
import gql from 'graphql-tag'
import { graphql } from 'react-apollo'
import {
  createSkeletonProvider,
  createSkeletonElement
} from '@trainline/react-skeletor'
import './Insight.css'

const POLLING_INTERVAL = 100000

const H2 = createSkeletonElement('h2', 'pending-home')
const Span = createSkeletonElement('span', 'pending-home')
const Div = createSkeletonElement('div', 'pending-home')

const Insight = ({
  Post = {
    loading: true,
    post: null
  }
}) => {
  const {post = {
    title: '',
    text: '',
    createdAt: null,
    username: null
  }} = Post
  return (
    <div className='page insight'>
      <Panel>
        <H2>
          {post.title}
        </H2>
        <Span style={{marginLeft: 2}}>
          by {post.username
            ? `${post.username}`
            : 'unknown author'}
        </Span>
        &nbsp;&#8226;&nbsp;
        {post.createdAt &&
          <Span>{moment(post.createdAt).format('MMM DD, YYYY')}</Span>}
        <Div>{post.text}</Div>
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

const withSkeleton = createSkeletonProvider(
  {
    Post: {
      loading: true,
      post: {
        title: '_____',
        link: 'https://sanbase.net',
        createdAt: new Date(),
        user: {
          username: ''
        }
      }
    }
  },
  ({ Post }) => Post.loading,
  () => ({
    backgroundColor: '#bdc3c7',
    color: '#bdc3c7'
  })
)(Insight)

export default enhance(withSkeleton)
