import React from 'react'
import { storiesOf } from '@storybook/react'
import HelpPopup from './../src/components/HelpPopup/HelpPopup'
import HelpPopupProjectsContent from './../src/components/HelpPopup/HelpPopupProjectsContent'

storiesOf('HelpPopup', module)
  .add('Projects overview help content', () => (
    <div style={{ padding: 20 }}>
      <HelpPopup>
        <HelpPopupProjectsContent />
      </HelpPopup>
    </div>
  ))
