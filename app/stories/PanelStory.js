import React from 'react'
import { storiesOf } from '@storybook/react'
import Panel from './../src/components/UI/Panel/Panel'
import ColorModeComparison from './ColorModeComparison'

storiesOf('Panel', module)
  .add('Simple', () => (
    <div>
      <ColorModeComparison>
        <Panel />
        <Panel>
          Lorem ipsum dolor sit amet consectetur adipisicing elit. Similique, illum?
        </Panel>
      </ColorModeComparison>
    </div>
  ))
  .add('Popup', () => (
    <div>
      <ColorModeComparison>
        <Panel popup />
        <Panel popup>
          Lorem ipsum dolor sit amet consectetur adipisicing elit. Similique, illum?
        </Panel>
      </ColorModeComparison>
    </div>
  ))
