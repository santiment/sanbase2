import React from 'react'
import { configure, addDecorator, setAddon  } from '@storybook/react'
import InfoAddon, { setDefaults } from '@storybook/addon-info'

// addon-info
setDefaults({
  header: false
})

addDecorator(story => <div style={{ padding: 20 }}>{story()}</div>)
setAddon(InfoAddon)

function loadStories () {
  require('../stories/index.js')
}

configure(loadStories, module)
