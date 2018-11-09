import React from 'react'
import { storiesOf } from '@storybook/react'
import Input from './../src/components/UI/Input/Input'
import ColorModeComparison from './ColorModeComparison'

storiesOf('Input', module).add('Simple', () => (
  <div>
    <ColorModeComparison>
      <Input defaultValue={'Built-in value'} />
      <Input placeholder={'Placeholder'} />
      <Input defaultValue={'inplace username'} inplace />
      <Input type='password' defaultValue={'inplace username'} readOnly />
    </ColorModeComparison>
  </div>
))
