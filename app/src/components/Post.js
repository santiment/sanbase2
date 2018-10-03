import React from 'react'
import moment from 'moment'
import { Link } from 'react-router-dom'
import { Label, Button } from 'semantic-ui-react'
import { createSkeletonElement } from '@trainline/react-skeletor'
import LikeBtn from './../pages/InsightsNew/LikeBtn'
import PostVisualBacktest from './PostVisualBacktest'
import './Post.css'

const A = createSkeletonElement('a', 'pending-home')
const Span = createSkeletonElement('span', 'pending-home')
const Div = createSkeletonElement('div', 'pending-home')

const STATES = {
  approved: 'approved',
  declined: 'declined',
  waiting: 'waiting',
  draft: 'draft',
  published: 'published'
}

const Status = ({ status = STATES.draft, moderationComment }) => {
  const color = (status => {
    if (status === STATES.published) {
      return 'green'
    }
    return 'orange'
  })(status)
  return (
    <Div className='post-status'>
      <div>
        <span>Status:</span> &nbsp;
        <Label size='tiny' basic color={color}>
          {status}
        </Label>
      </div>
      {moderationComment && (
        <div>
          <span>Comment:</span> {moderationComment}
        </div>
      )}
    </Div>
  )
}

const Author = ({ id, username }) => (
  <div className='event-post-author'>
    by <Link to={`/insights/users/${id}`}>{username}</Link>
  </div>
)

export const Post = ({
  index = 1,
  id,
  title,
  votes = {},
  liked = false,
  user,
  tags = [],
  balance = null,
  createdAt,
  updatedAt,
  votedAt,
  votePost,
  unvotePost,
  deletePost,
  publishPost,
  moderationComment = null,
  state = STATES.approved,
  readyState = STATES.draft,
  discourseTopicUrl = '',
  gotoInsight,
  showStatus = false
}) => {
  return (
    <div className='event-post'>
      <div
        onClick={e => {
          id && gotoInsight(id)
        }}
        className='event-post-body'
      >
        <div>
          {tags.length > 0 && (
            <div className='post-tags'>
              {tags.map((tag, index) => (
                <Link
                  key={index}
                  className='post-tag'
                  to={`/insights/tags/${tag.name}`}
                >
                  {tag.label || tag.name}
                </Link>
              ))}
            </div>
          )}
          <A className='event-storylink' href={`/insights/${id}`}>
            {title}
          </A>
          <div className='post-date-author'>
            <Span>{moment(createdAt).format('MMM DD, YYYY')}</Span>
            &nbsp;•&nbsp;
            {user && user.id && <Author {...user} />}
          </div>
        </div>
        {createdAt &&
          tags.length > 0 && (
          <PostVisualBacktest
            from={createdAt}
            ticker={tags[0].name}
            updatedAt={updatedAt}
          />
        )}
      </div>
      {user &&
        !showStatus && (
        <Div className='event-post-info'>
          {discourseTopicUrl && (
            <a className='discussion-btn' href={discourseTopicUrl}>
                Comments
            </a>
          )}
          <LikeBtn
            onLike={() => {
              if (votedAt) {
                unvotePost(id)
              } else {
                votePost(id)
              }
            }}
            balance={balance}
            liked={!!votedAt}
            votes={votes}
          />
        </Div>
      )}
      {showStatus && (
        <Div className='event-post-controls'>
          <Status moderationComment={moderationComment} status={readyState} />
          {readyState === 'draft' && (
            <div style={{ display: 'flex' }}>
              <Button
                size='mini'
                onClick={() => deletePost(id)}
                basic
                style={{
                  fontWeight: '700',
                  color: '#db2828'
                }}
              >
                Delete this insight
              </Button>
              <Button
                size='mini'
                color='orange'
                onClick={() => publishPost(id)}
                style={{
                  fontWeight: '700'
                }}
              >
                Publish your insight
              </Button>
            </div>
          )}
        </Div>
      )}
    </div>
  )
}

export default Post
