import React from 'react'
import { storiesOf } from '@storybook/react'
import { action } from '@storybook/addon-actions'
import ShareOptions from './../src/components/ShareOptions/ShareOptions'

const stories = storiesOf('ShareOptions', module)

const ShareOptionsExample = () => (
  <ShareOptions
    url='https://localhost:3000'
    title='Any message' />
)

stories.add('ShareOptions', ShareOptionsExample)

stories.addWithInfo(
  'ShareOptions (usage info)',
  `
    ShareOptions component is the list of "share" buttons.


    ~~~js
      <ShareOptions
        url='https://localhost:3000'
        title='Any message' />
    ~~~
  `, ShareOptionsExample, { inline: true, source: false }
)
