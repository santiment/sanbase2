import React from 'react'
import { storiesOf } from '@storybook/react'

const styles = {
  main: {
    margin: 15,
    maxWidth: 600,
    lineHeight: 1
  }
}

const Welcome = props => (
  <div style={styles.main}>
    <h1>React Components for Sanbase</h1>
    <p>
      Use the links on the left to see variations of usage, with different props.
    </p>
    <p>
      See also&nbsp;
      <a href='https://github.com/santiment/sanbase2'>Github link</a>
    </p>
  </div>
)

storiesOf('Welcome', module)
  .add('to Sanbase', () => (
    <Welcome />
  ))
