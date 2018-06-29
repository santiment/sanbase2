import React from 'react'
import { storiesOf } from '@storybook/react'
import { CreateInsight } from './../src/pages/InsightsNew/CreateInsight'

storiesOf('Insights', module)
  .add('Insight\'s editor', () => (
    <div style={{ padding: '20px' }}>
      <CreateInsight />
    </div>
  ))
