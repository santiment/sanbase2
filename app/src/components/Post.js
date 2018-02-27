import React from 'react'
import moment from 'moment'
import { Label, Button } from 'semantic-ui-react'
import LikeBtn from './../pages/EventVotesNew/LikeBtn'
import { createSkeletonElement } from '@trainline/react-skeletor'
import './Post.css'

export const getSourceLink = (link = '') => {
  return link.split('/')[2]
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
      {moderationComment && <div>
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
  moderationComment = null,
  state = STATES.waiting,
  showStatus = false
}) => {
  return (
    <div className='event-post'>
      <div className='event-post-index'>
        {index}.
      </div>
      <div className='event-post-body'>
        <A className='event-storylink' href={link}>
          {title}
        </A>
        <br />
        <Span>{getSourceLink(link)}</Span>&nbsp;&#8226;&nbsp;
        <Span>{moment(createdAt).format('MMM DD, YYYY')}</Span>
        {user &&
          <Div className='event-post-info'>
            by&nbsp; {user.username}
          </Div>}
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
        {showStatus && <Status
          moderationComment={moderationComment}
          status={!state ? STATES.waiting : state} />}
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
  )
}

export default Post
