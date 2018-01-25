import React from 'react'
import Username from './Username'
import LikeBtn from './../pages/EventVotesNew/LikeBtn'
import './Post.css'

export const getSourceLink = link => {
  return link.split('/')[2]
}

const Post = ({
  index = 1,
  title,
  link,
  votes = 0,
  liked = false,
  author,
  createdAt,
  commentCounts = 0
}) => {
  return (
    <div className='event-post'>
      <div className='event-post-index'>
        {index}.
      </div>
      <div className='event-post-body'>
        <a className='event-storylink' href={link}>
          {title}
        </a>&nbsp;
        ({getSourceLink(link)})
        <div className='event-post-info'>
          by&nbsp;<Username address={author} /> {createdAt} &nbsp;
          <LikeBtn
            onLike={liked => console.log('like')}
            liked={liked}
            votes={votes} />
          <div className='event-post-votes'>
            {commentCounts} {commentCounts === 1 ? 'comment' : 'comments'}
          </div>
        </div>
      </div>
    </div>
  )
}

export default Post
