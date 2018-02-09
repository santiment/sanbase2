import React from 'react'
import { Card, Button, Statistic, Label, Icon } from 'semantic-ui-react'
import ProjectIcon from './../../components/ProjectIcon'
import PercentChanges from './../../components/PercentChanges'
import { formatNumber } from '../../utils/formatting'
import { millify } from '../../utils/utils'

const HiddenElements = () => ''
// Project Name
// Market Cap
// Crypto Balance (ETH) - the current Balance column
// ETH Spent (30d) - total change in ETH balance for the last 30 days
// Dev Activity (30d) - total dev activity for the last 30 days
// Flag - signals flag. For now we only show it when Crypto Balance > Market Cap

const MARKET_SEGMENT_COLORS = {
  'Financial': 'violet',
  'Media': 'yellow',
  'Blockchain Network': 'teal',
  'Prediction Market': 'olive',
  'Advertising': 'orange',
  'Transportation': 'grey',
  'Gambling': 'red',
  'Gaming': 'green',
  'Legal': 'pink',
  'Protocol': 'teal',
  'Digital Identity': 'teal',
  'Data': 'black'
}

const StatisticElement = ({name, value, up = undefined, disabled = false}) => (
  <Statistic style={{
    color: disabled ? '#d3d3d3' : 'initial'
  }}>
    <Statistic.Label>{name}</Statistic.Label>
    <Statistic.Value>
      {typeof up !== 'undefined' && value !== '---'
        ? <PercentChanges changes={value} />
        : value}
    </Statistic.Value>
  </Statistic>
)

const ProjectCard = ({
  name,
  rank,
  ticker,
  description,
  marketSegment,
  priceUsd,
  percentChange24h,
  volumeUsd,
  volumeUsd24h,
  githubData,
  twitterData,
  btcBalance = 0,
  ethBalance = 0,
  marketcapUsd,
  teamTokenWallet,
  warning = false
}) => {
  return (
    <Card fluid >
      <Card.Content>
        <Card.Header>
          <div style={{display: 'flex', alignItems: 'center', justifyContent: 'space-between'}}>
            <div style={{display: 'flex', alignItems: 'center'}}>
              <ProjectIcon name={ticker} />
              {name}
            </div>
            <div style={{
              textTransform: 'uppercase',
              letterSpacing: '0.5px',
              top: '12px',
              fontSize: '12px',
              position: 'absolute',
              right: '14px',
              color: 'rgba(0,0,0,.68)'
            }}
            ><span>rank</span> {rank}</div>
          </div>
        </Card.Header>
        {marketSegment && <Card.Meta>
          <Label
            size='mini'
            color={MARKET_SEGMENT_COLORS[marketSegment]} tag>
            {marketSegment}
          </Label>
        </Card.Meta>}
        <Card.Description>
          {!description
            ? "We don't have any description about this project yet."
            : description}
        </Card.Description>
      </Card.Content>
      <Card.Content extra>
        {warning &&
        <Label color='orange' ribbon>
          <Icon name='warning sign' />
        </Label>}
        <Statistic.Group size='mini' widths='two' style={{paddingBottom: '1em'}}>
          <StatisticElement
            name='Price'
            value={priceUsd ? formatNumber(priceUsd, 'USD') : '---'}
            disabled={!priceUsd} />
          <StatisticElement
            name='Volume'
            value={volumeUsd ? millify(parseFloat(volumeUsd)) : '---'}
            disabled={!volumeUsd} />
          <StatisticElement
            name='24h Price'
            up={percentChange24h > 0}
            value={percentChange24h || '---'}
            disabled={!percentChange24h} />
          <StatisticElement
            name='24h Volume'
            up={volumeUsd24h > 0}
            value={volumeUsd24h || '---'}
            disabled={!volumeUsd24h} />
          <StatisticElement
            name='MarketCap'
            value={marketcapUsd ? millify(parseFloat(marketcapUsd)) : '---'}
            disabled={!marketcapUsd} />
          <StatisticElement
            name='Crypto Balance'
            value={ethBalance ? millify(parseFloat(ethBalance)) : '---'}
            disabled={!ethBalance} />
          <StatisticElement
            name='Dev Activity 30d'
            value={githubData || '---'}
            disabled={!githubData} />
          <StatisticElement
            name='Twitter 30d'
            value={twitterData || '---'}
            disabled={!twitterData} />
        </Statistic.Group>
      </Card.Content>
      <HiddenElements>
        <Card.Content extra>
          <div className='ui two buttons'>
            <Button basic size='large' icon='star' />
            <Button basic size='large'>more...</Button>
          </div>
        </Card.Content>
      </HiddenElements>
    </Card>
  )
}

export default ProjectCard
