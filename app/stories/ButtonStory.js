import React from 'react'
import { storiesOf } from '@storybook/react'
import Button from './../src/components/UI/Button/Button'

storiesOf('Button', module)
  .add('Filled', () => (
    <div>
      <div>
        <Button fill='negative'>Negative fill</Button>
      </div>
      <br />
      <div>
        <Button fill='positive'>Positive fill</Button>
      </div>
    </div>
  ))
  .add('Bordered', () => (
    <div>
      <div>
        <Button border='negative'>Negative border</Button>
      </div>
      <br />
      <div>
        <Button border='positive'>Positive border</Button>
      </div>
    </div>
  ))
