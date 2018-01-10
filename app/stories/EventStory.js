import React from 'react'
import { storiesOf } from '@storybook/react'
// import { action } from '@storybook/addon-actions'
import Post from './../src/components/Post'
import PostsList from './../src/components/PostsList'
import EventVotesNew from './../src/pages/EventVotesNew.js'

const posts = {
  'asffe2f2f': {
    title: 'Ripple pump!',
    link: 'https://medium.com',
    votes: 25,
    author: 'sdfefw',
    created: new Date()
  },
  'a23429r3f': {
    title: 'Eth pump!',
    link: 'https://medium.com',
    votes: 95,
    author: 'jcasdfiu',
    created: new Date()
  },
  'asf2342ff': {
    title: 'Gcoin pump!',
    link: 'https://medium.com',
    votes: 15,
    author: 'jcasdfiu',
    created: new Date()
  }
}

storiesOf('Event Votes', module)
  .add('Post', () => (
    <div>
        Post component in EventVotes page
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
  .add('Post Create Form', () => (
    <div style={{margin: 20}}>
      <EventVotesNew />
    </div>
  ))
