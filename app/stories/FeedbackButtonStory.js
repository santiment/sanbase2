import React from 'react'
import { storiesOf } from '@storybook/react'
import { action } from '@storybook/addon-actions'
import SmoothDropdown from './../src/components/SmoothDropdown/SmoothDropdown'
import { FeedbackButton } from './../src/components/FeedbackButton/FeedbackButton'

const stories = storiesOf('FeedbackButton', module)

const FeedbackButtonExample = () => (
  <SmoothDropdown>
    <FeedbackButton />
  </SmoothDropdown>
)

stories.add('FeedbackButtonExample', FeedbackButtonExample)
