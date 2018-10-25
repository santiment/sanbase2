import React from 'react'
import { storiesOf } from '@storybook/react'
import Button from './../src/components/UI/Button/Button'

storiesOf('Button', module)
  .add('', () => <Button>Test text</Button>)
  .add('Filled buttons', () => (
    <div>
      <Button fill='red'>Test</Button>
      <Button fill='green'>Test</Button>
    </div>
  ))
