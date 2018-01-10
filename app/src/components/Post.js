import React from 'react'
import './Post.css'

export const getSourceLink = link => {
  return link.split('/')[2]
}

const Post = ({
  index = 1,
  title,
  link,
  votes = 0,
  author,
  createdAt,
  commentCounts = 0
}) => {
  return (
    <div className='event-post'>
      <div className='event-post-index'>
        {index}.
      </div>
      <div>
        <a className='event-storylink' href={link}>{title}</a> ({getSourceLink(link)})
        <div className='event-post-info'>
          by {author} {createdAt} &nbsp;
          <div className='event-post-votes'>
            <i className='fa fa-caret-up' />&nbsp;
            {votes}
          </div>
          <div className='event-post-votes'>
            {commentCounts} {commentCounts === 1 ? 'comment' : 'comments'}
          </div>
        </div>
      </div>
    </div>
  )
}

export default Post
