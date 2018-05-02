import React, { createElement } from 'react'
import { Redirect, withRouter } from 'react-router-dom'
import {
  compose,
  pure
} from 'recompose'
import moment from 'moment'
import { Button } from 'semantic-ui-react'
import gql from 'graphql-tag'
import { graphql } from 'react-apollo'
import {
  createSkeletonProvider,
  createSkeletonElement
} from '@trainline/react-skeletor'
import marksy from 'marksy'
import InsightsLayout from './InsightsLayout'
import Panel from './../../components/Panel'
import './Insight.css'

const POLLING_INTERVAL = 100000

const H2 = createSkeletonElement('h2', 'pending-home')
const Span = createSkeletonElement('span', 'pending-home')
const Div = createSkeletonElement('div', 'pending-home')

const Insight = ({
  history,
  Post = {
    loading: true,
    post: null
  }
}) => {
  const {post = {
    title: '',
    text: '',
    createdAt: null,
    user: {
      username: null
    },
    readyState: 'draft'
  }} = Post
  const compile = marksy({
    createElement,
    h1 (props) {
      return <h1 style={{ textDecoration: 'underline' }}>{props.children}</h1>
    }
  })
  if (!post) {
    return <Redirect to='/insights' />
  }
  return (
    <div className='insight'>
      <InsightsLayout
        isLogin={false}
        title={`SANbase: Insight - ${post.title}`}>
        <Panel className='insight-panel'>
          <H2>
            {post.title} {post.readyState === 'draft' &&
              <Button
                onClick={() => {
                  history.push(`/insights/update/${post.id}`, {post})
                }}
              >
                edit
              </Button>
            }

          </H2>
          <Span>
            by {post.user.username
              ? <a href={`/insights/users/${post.user.id}`}>{post.user.username}</a>
              : 'unknown author'}
          </Span>
          &nbsp;&#8226;&nbsp;
          {post.createdAt &&
            <Span>{moment(post.createdAt).format('MMM DD, YYYY')}</Span>}
          <Div className='insight-content' style={{ marginTop: '1em' }}>
            {post.text &&
              compile(post.text).tree}
          </Div>
        </Panel>
      </InsightsLayout>
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
      readyState
      user {
        username
        id
      }
      votedAt
      votes {
         totalSanVotes,
         totalVotes
      }
    }
  }
`

const enhance = compose(
  withRouter,
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
