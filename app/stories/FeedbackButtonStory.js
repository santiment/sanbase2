import React from 'react'
import { storiesOf } from '@storybook/react'
import { action } from '@storybook/addon-actions'
import SmoothDropdown from './../src/components/SmoothDropdown/SmoothDropdown'
import { FeedbackButton } from './../src/components/FeedbackButton/FeedbackButton'

const stories = storiesOf('FeedbackButton', module)

const FeedbackButtonExample = () => (
  <SmoothDropdown>
    <div style={{
      background: 'linear-gradient(270deg, #26a987, #2d79d0, #309d81)',
      padding: 12
    }}>
      <FeedbackButton />
    </div>
  </SmoothDropdown>
)

stories.add('FeedbackButtonExample', FeedbackButtonExample)
