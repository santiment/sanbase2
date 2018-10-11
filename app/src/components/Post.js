import React from 'react'
import moment from 'moment'
import { withRouter } from 'react-router-dom'
import { Label, Button } from 'semantic-ui-react'
import LikeBtn from './../pages/EventVotesNew/LikeBtn'
import { createSkeletonElement } from '@trainline/react-skeletor'
import './Post.css'

export const getSourceLink = (link = '') => {
  return link.split('/')[2] || 'sanbase.net'
}

const A = createSkeletonElement('a', 'pending-home')
const Span = createSkeletonElement('span', 'pending-home')
const Div = createSkeletonElement('div', 'pending-home')

const STATES = {
  approved: 'approved',
  declined: 'declined',
  waiting: 'waiting'
}

const Status = ({status = STATES.waiting, moderationComment}) => {
  const color = (status => {
    if (status === STATES.approved) {
      return 'green'
    } else if (status === STATES.declined) {
      return 'red'
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

const Post = ({
  index = 1,
  id,
  title,
  link,
  totalSanVotes = 0,
  liked = false,
  user,
  createdAt,
  votedAt,
  votePost,
  unvotePost,
  deletePost,
  history,
  moderationComment = null,
  state = STATES.approved,
  showStatus = false
}) => {
  return (
    <div className='event-post' onClick={e => {
      if (e.target.className === 'event-post-body') {
        history.push(`/insights/${id}`)
      }
    }}>
      <div className='event-post-body'>
        <A className='event-storylink' href={link || `/insights/${id}`}>
          {title}
        </A>
        <br />
        <Span>{getSourceLink(link)}</Span>&nbsp;&#8226;&nbsp;
        <Span>{moment(createdAt).format('MMM DD, YYYY')}</Span>
        {user &&
          <Div className='event-post-info'>
            <div className='event-post-author'>
              by&nbsp; <a href={`/insights/users/${user.id}`}>{user.username}</a>
            </div>
            <LikeBtn
              onLike={() => {
                if (votedAt) {
                  unvotePost(id)
                } else {
                  votePost(id)
                }
              }}
              liked={!!votedAt}
              votes={totalSanVotes} />
          </Div>}
        <div className='event-post-controls'>
          {showStatus && <Status
            moderationComment={moderationComment}
            status={!state ? STATES.approved : state} />}
          {showStatus && <Button
            size='mini'
            onClick={() => deletePost(id)}
            style={{
              fontWeight: '700',
              color: '#db2828'
            }}>
            Delete this insight
          </Button>}
        </div>
      </div>
    </div>
  )
}

export default withRouter(Post)
