import React from 'react'
import moment from 'moment'
import Username from './Username'
import LikeBtn from './../pages/EventVotesNew/LikeBtn'
import { createSkeletonElement } from '@trainline/react-skeletor'
import './Post.css'

export const getSourceLink = (link = '') => {
  return link.split('/')[2]
}

const A = createSkeletonElement('a', 'pending-home')
const Span = createSkeletonElement('span', 'pending-home')
const Div = createSkeletonElement('div', 'pending-home')

const Post = ({
  index = 1,
  id,
  title,
  link,
  totalSanVotes = 0,
  liked = false,
  user,
  approvedAt,
  votedAt,
  votePost,
  unvotePost
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
        <Span>{moment(approvedAt).format('MMM DD, YYYY')}</Span>
        <Div className='event-post-info'>
          by&nbsp;{user && <Username address={user.username} />}
        </Div>
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
      </div>
    </div>
  )
}

export default Post
