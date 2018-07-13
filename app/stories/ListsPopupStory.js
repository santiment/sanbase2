import React from 'react'
import { storiesOf } from '@storybook/react'
import ListsPopup from './../src/components/ListsPopup/ListsPopup.js'

const exampleLists = ['Portfolio 1', 'Portfolio 2', 'Anka List']

storiesOf('ListsPopup', module)
  .add('List of favorite projects', () => (
    <div style={{ padding: 20 }}>
      <ListsPopup lists={exampleLists} />
    </div>
  ))
