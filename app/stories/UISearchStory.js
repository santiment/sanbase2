import React from 'react'
import { storiesOf } from '@storybook/react'
import Search from './../src/components/UI/Search/Search'
import ColorModeComparison from './ColorModeComparison'

storiesOf('Search', module).add('Simple', () => (
  <div>
    <ColorModeComparison>
      <Search defaultValue={'Built-in value'} />
    </ColorModeComparison>
  </div>
))
