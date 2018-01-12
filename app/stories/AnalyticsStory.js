import React from 'react'
import { storiesOf } from '@storybook/react'
import Analytics from './../src/components/Analytics.js'
import Panel from './../src/components/Panel.js'
import twitterHistory from './twitter_history_1month.json'

const twitter = {
  data: {
    loading: false,
    followersCount: 2343
  },
  history: {
    loading: false,
    items: twitterHistory
  }
}

storiesOf('Analytics', module)
  .add('with twitter', () => (
    <div style={{margin: 20, maxWidth: 720}}>
      <Panel withoutHeader>
        <Analytics twitter={twitter} />
      </Panel>
    </div>
  ))
