import React from 'react'
import { storiesOf } from '@storybook/react'
import Button from './../src/components/UI/Button/Button'
import ColorModeComparison from './ColorModeComparison'

storiesOf('Button', module)
  .add('Filled', () => (
    <div>
      <ColorModeComparison>
        <Button fill='grey'>Grey fill</Button>
        <Button fill='negative'>Negative fill</Button>
        <Button fill='positive'>Positive fill</Button>
        <Button fill='purple'>Purple fill</Button>
      </ColorModeComparison>
    </div>
  ))
  .add('Bordered', () => (
    <div>
      <ColorModeComparison>
        <Button border='negative'>Negative border</Button>
        <Button border='positive'>Positive border</Button>
        <Button border='purple'>Purple border</Button>
      </ColorModeComparison>
    </div>
  ))
