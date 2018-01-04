import React from 'react'
import { storiesOf } from '@storybook/react'
import PanelBlock from './../src/components/PanelBlock'
import GeneralInfoBlock from './../src/components/GeneralInfoBlock'

storiesOf('Project Detailted Page', module)
  .add('General Info Block', () => (
    <PanelBlock
      isUnauthorized={false}
      isLoading={false}
      title='General Info'>
      <GeneralInfoBlock
        btcBalance={null}
        facebookLink={null}
        fundsRaisedIcos={[]}
        githubLink={null}
        id={15}
        marketCapUsd={null}
        name={'Aragon'}
        projectTransprency={false}
        projectTransparencyDescription={null}
        projectTransparencyStatus={null}
        redditLink={null}
        slackLink={null}
        ticker={'ANT'}
        tokenAddress={null}
        twitterLink={null}
        volume={'1432780'}
        websiteLink={'https://aragon.one/'}
        whitepaperLink={null} />
    </PanelBlock>
  ))
