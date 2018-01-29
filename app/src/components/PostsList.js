import React from 'react'
import { createSkeletonProvider } from '@trainline/react-skeletor'
import Post from './Post.js'
import './PostsList.css'

const PostsList = ({
  posts = [],
  loading = true,
  isError = false,
  isEmpty = true,
  votePost
}) => {
  return (
    <div className='event-posts-list'>
      {Object.keys(posts).map((postKey, index) => (
        <Post
          index={index + 1}
          key={index}
          votePost={votePost}
          {...posts[postKey]} />
      ))}
    </div>
  )
}

export default createSkeletonProvider(
  {
    posts: [{
      title: '_____',
      link: 'https://sanbase.net',
      approvedAt: new Date(),
      user: {
        username: ''
      }
    }, {
      title: '_____',
      link: 'https://sanbase.net',
      approvedAt: new Date(),
      user: {
        username: ''
      }
    }]
  },
  ({ posts }) => posts.length === 0,
  () => ({
    backgroundColor: '#bdc3c7',
    color: '#bdc3c7'
  })
)(PostsList)
