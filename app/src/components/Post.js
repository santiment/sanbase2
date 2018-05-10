import React, { Fragment } from 'react'
import moment from 'moment'
import { withRouter } from 'react-router-dom'
import { Label, Button } from 'semantic-ui-react'
import LikeBtn from './../pages/EventVotesNew/LikeBtn'
import { createSkeletonElement } from '@trainline/react-skeletor'
import './Post.css'

export const getSourceLink = link => {
  return link ? link.split('/')[2] : 'SANbase.net'
}

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

const Status = ({status = STATES.draft, moderationComment}) => {
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
        <Label
          size='tiny'
          basic
          color={color}>
          {status}
        </Label>
      </div>
      {moderationComment &&
        <div>
          <span>Comment:</span> {moderationComment}
        </div>}
    </Div>
  )
}

const Author = ({id, username}) => (
  <div className='event-post-author'>
    {id &&
      <Fragment>
        by&nbsp; <a href={`/insights/users/${id}`}>{username}</a>
      </Fragment>}
  </div>
)

const Post = ({
  index = 1,
  id,
  title,
  link,
  votes = {},
  liked = false,
  user,
  tags = [],
  balance = null,
  createdAt,
  votedAt,
  votePost,
  unvotePost,
  deletePost,
  publishPost,
  history,
  moderationComment = null,
  state = STATES.approved,
  readyState = STATES.draft,
  gotoInsight,
  showStatus = false
}) => {
  return (
    <div className='event-post' onClick={e => {
      if (e.target.className === 'event-post-body') {
        id && gotoInsight(id)
      }
    }}>
      <div className='event-post-body'>
        <A className='event-storylink' href={link || `/insights/${id}`}>
          {title}
        </A>
        <br />
        <Span>{getSourceLink(link)}</Span>&nbsp;&#8226;&nbsp;
        <Span>{moment(createdAt).format('MMM DD, YYYY')}</Span>
        {user && tags.length > 0 && <Author {...user} />}
        {user &&
          <Div className='event-post-info'>
            {tags.length > 0
              ? <div className='post-tags'>
                {tags.map((tag, index) => (
                  <div key={index} className='post-tag'>{tag.label || tag.name}</div>
                ))}
              </div>
              : <Author {...user} />}
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
              votes={votes.totalSanVotes || 0} />
          </Div>}
        <Div className='event-post-controls'>
          {showStatus && <Status
            moderationComment={moderationComment}
            status={readyState} />}
          <div style={{
            display: 'flex'
          }} >
            {showStatus && readyState === 'draft' && <Button
              size='mini'
              onClick={() => deletePost(id)}
              basic
              style={{
                fontWeight: '700',
                color: '#db2828'
              }}>
              Delete this insight
            </Button>}
            {showStatus && readyState === 'draft' && <Button
              size='mini'
              color='orange'
              onClick={() => publishPost(id)}
              style={{
                fontWeight: '700'
              }}>
              Publish your insight
            </Button>}
          </div>
        </Div>
      </div>
    </div>
  )
}

export default withRouter(Post)
