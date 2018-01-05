import React from 'react'
import { storiesOf } from '@storybook/react'
import { Button, Message } from 'semantic-ui-react'
import Panel from './../src/components/Panel'

storiesOf('Standards', module)
  .add('How to use standard components?', () => (
    <Panel>
      <p>We use react-semantic</p>
      <p>You can read more about usage in <a href='https://react.semantic-ui.com/'>documentation</a>
      </p>
    </Panel>
  ))
  .add('Panel default', () => (
    <Panel>
      <h1>This is a panel</h1>
    </Panel>
  ))
  .add('Buttons', () => (
    <div>
      <p>
        <a href='https://react.semantic-ui.com/elements/button'>documentation about buttons</a>
      </p>
      <Button>button</Button>
      <Button basic>basic button</Button>
      <Button basic color='red'>button with red color</Button>
    </div>
  ))
  .add('Messages', () => (
    <div>
      <p>
        <a href='https://react.semantic-ui.com/elements/messages'>documentation about messages</a>
      </p>
      <Message>Any message</Message>
      <Message negative>Negative message</Message>
    </div>
  ))
