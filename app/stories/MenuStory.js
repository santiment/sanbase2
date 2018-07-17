import React from 'react'
import { storiesOf } from '@storybook/react'
import { BrowserRouter as Router } from 'react-router-dom'
import { Analysis } from './../src/components/TopMenu.js'

storiesOf('Menu', module)
  .add('TopMenu', () => (
    <div style={{ padding: 20 }}>
      <Router>
        <Analysis />
      </Router>
    </div>
  ))
