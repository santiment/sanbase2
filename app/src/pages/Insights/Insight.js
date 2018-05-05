import React, { Component } from 'react'
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
import { convertToRaw } from 'draft-js'
import { Editor, createEditorState } from 'medium-draft'
import mediumDraftImporter from 'medium-draft/lib/importer'
import 'medium-draft/lib/index.css'
import InsightsLayout from './InsightsLayout'
import Panel from './../../components/Panel'
import './Insight.css'

const POLLING_INTERVAL = 100000

const H2 = createSkeletonElement('h2', 'pending-home')
const Span = createSkeletonElement('span', 'pending-home')
const Div = createSkeletonElement('div', 'pending-home')

class Insight extends Component {
  constructor (props) {
    super(props)

    this.state = {
      editorState: createEditorState()
    }
  }

  componentWillReceiveProps (nextProps) {
    if (nextProps.Post.post.text) {
      this.setState({
        editorState: createEditorState(convertToRaw(mediumDraftImporter(nextProps.Post.post.text)))
      })
    }
  }

  render () {
    const {history,
      Post = {
        loading: true,
        post: null
      }
    } = this.props
    const {post = {
      title: '',
      text: '',
      createdAt: null,
      user: {
        username: null
      },
      readyState: 'draft'
    }} = Post
    const {editorState} = this.state

    if (!post) {
      return <Redirect to='/insights' />
    }

    return (
      <div className='insight'>
        <InsightsLayout
          isLogin={false}
          title={`SANbase: Insight - ${post.title}`}>
          <Panel className='insight-panel'>
            <div className='insight-panel-header'>
              <H2>
                {post.title}
              </H2>
              {post.readyState === 'draft' &&
                <Button
                  basic
                  onClick={() => {
                    history.push(`/insights/update/${post.id}`, {post})
                  }}
                >
                  edit
                </Button>}
            </div>
            <Span>
              by {post.user.username
                ? <a href={`/insights/users/${post.user.id}`}>{post.user.username}</a>
                : 'unknown author'}
            </Span>
            &nbsp;&#8226;&nbsp;
            {post.createdAt &&
              <Span>{moment(post.createdAt).format('MMM DD, YYYY')}</Span>}
            <Div className='insight-content' style={{ marginTop: '1em' }}
            >
              <Editor
                editorEnabled={false}
                editorState={editorState}
                disableToolbar
                onChange={() => {}}
              />
            </Div>
          </Panel>
        </InsightsLayout>
      </div>
    )
  }
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
