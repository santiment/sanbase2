import React from 'react'
import { storiesOf } from '@storybook/react'
// import { action } from '@storybook/addon-actions'
import Post from './../src/components/Post'
import PostsList from './../src/components/PostsList'
import EventVotesNew from './../src/pages/EventVotesNew/EventVotesNew.js'

const posts = {
  'asffe2f2f': {
    title: 'Ripple pump!',
    link: 'https://medium.com',
    user: {
      id: 23,
      username: 'Yura Z.'
    },
    state: 'approved',
    votes: 25,
    createdAt: new Date()
  },
  'a2ffe2f2f': {
    title: 'Btc pump!',
    link: 'https://medium.com',
    user: {
      id: 23,
      username: 'Yura Z.'
    },
    state: null,
    createdAt: new Date()
  },
  'a23429r3f': {
    title: 'Eth pump!',
    link: 'https://medium.com',
    user: {
      id: 23,
      username: 'Anka Z.'
    },
    state: 'declined',
    moderationComment: 'Any reason of declined',
    votes: 95,
    author: 'jcasdfiu',
    createdAt: new Date()
  },
  'asf2342ff': {
    title: 'Gcoin pump!',
    link: 'https://medium.com',
    user: {
      id: 13
    },
    votes: 15,
    author: 'jcasdfiu',
    createdAt: new Date()
  }
}

storiesOf('Event Votes', module)
  .add('Post', () => (
    <div>
        Post component in Insights page
      <hr />
      <div style={{margin: 20}}>
        <Post {...posts['asf2342ff']} />
      </div>
    </div>
  ))
  .add('Posts List', () => (
    <div style={{margin: 20}}>
      <PostsList posts={posts} />
    </div>
  ))
  .add("User's list of insights", () => (
    <div style={{margin: 20}}>
      <PostsList userId={23} posts={posts} />
    </div>
  ))
  .add('Post Create Form', () => (
    <div style={{margin: 20}}>
      <EventVotesNew />
    </div>
  ))
