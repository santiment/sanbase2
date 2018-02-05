import React from 'react'
import { createSkeletonProvider } from '@trainline/react-skeletor'
import Post from './Post.js'
import './PostsList.css'

const PostsList = ({
  posts = {},
  userId = null,
  loading = true,
  isError = false,
  isEmpty = true,
  votePost,
  unvotePost
}) => {
  const postKeys = userId
    ? Object.keys(posts)
        .filter(postKey => posts[postKey].user.id === userId)
    : Object.keys(posts)
  return (
    <div className='event-posts-list'>
      {postKeys.map((postKey, index) => (
        <Post
          showStatus={!!userId}
          index={index + 1}
          key={index}
          votePost={votePost}
          unvotePost={unvotePost}
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
      createdAt: new Date(),
      user: {
        username: ''
      }
    }, {
      title: '_____',
      link: 'https://sanbase.net',
      createdAt: new Date(),
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
