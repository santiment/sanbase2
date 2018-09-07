import React from 'react'
import { storiesOf } from '@storybook/react'
import { action } from '@storybook/addon-actions'
import TimeFilter from './../src/components/TimeFilter/TimeFilter'

const stories = storiesOf('TimeFilter', module)

const TimeFilterExample = () => (
  <TimeFilter
    timeOptions={['1w', '1m', '3m', 'all']}
    onSelectOption={action('clicked')}
    defaultSelected='1w' />
)

stories.add('TimeFilter', TimeFilterExample)

stories.add('TimeFilter: disabled', () => (
  <TimeFilter disabled />
))

stories.addWithInfo(
  'TimeFilter (usage info)',
  `
    TimeFilter component is made for Charts filter.


    ~~~js
      const onSelectOption = (newSelectedOption) => console.log(newSelectedOption)

      <TimeFilter
        onSelectOption={onSelectOption}
        timeOptions={['1w', '1m', '3m', 'all']}
        defaultSelected='1w' />
    ~~~
  `, TimeFilterExample, { inline: true, source: false }
)
