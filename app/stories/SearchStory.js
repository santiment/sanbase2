import React from 'react'
import { storiesOf } from '@storybook/react'
import { action } from '@storybook/addon-actions'
import Search from './../src/components/Search'

const projects = [{
  name: 'Santiment',
  ticker: 'SAN'
}, {
  name: 'EOS',
  ticker: 'EOS'
}]

storiesOf('Search', module)
  .add('with projects', () => (
    <div>
      <p>Search data = {JSON.stringify(projects)}</p>
      <hr />
      <Search
        onSelectProject={action('handle selected Project')}
        projects={projects} />
    </div>
  ))
