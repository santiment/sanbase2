import React from 'react'
import { storiesOf } from '@storybook/react'
import { action } from '@storybook/addon-actions'
import Selector from './../src/components/Selector/Selector'

const stories = storiesOf('Selector', module)

const SelectorExample = () => (
  <Selector
    options={['1w', '1m', '3m', 'all']}
    onSelectOption={action('clicked')}
    defaultSelected='1w' />
)

stories.add('Selector', SelectorExample)

stories.add('Selector: disabled', () => (
  <Selector options={['case 1', 'case 2']} disabled />
))

stories.addWithInfo(
  'Selector (usage info)',
  `
    Selector component is made for Charts filter.


    ~~~js
      const onSelectOption = (newSelectedOption) => console.log(newSelectedOption)

      <Selector
        onSelectOption={onSelectOption}
        options={['1w', '1m', '3m', 'all']}
        defaultSelected='1w' />
    ~~~
  `, SelectorExample, { inline: true, source: false }
)
