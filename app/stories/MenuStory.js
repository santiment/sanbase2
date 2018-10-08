import React from 'react'
import { storiesOf } from '@storybook/react'
import StoryRouter from 'storybook-react-router'
import DesktopMenuLinkContainer
  from './../src/components/DesktopMenu/DesktopMenuLinkContainer'
import DesktopAnalysisMenu
  from './../src/components/DesktopMenu/DesktopAnalysisMenu'

const stories = storiesOf('Menu', module)
stories.addDecorator(StoryRouter())
stories.add('Dropdown Top Submenu', () => (
  <DesktopMenuLinkContainer
    title='Insights'
    description='Check'
    linkIcon='insights'
    to='/insights'
  />
))
stories.add('Dropdown Top', () => <DesktopAnalysisMenu />)
