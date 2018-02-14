import React from 'react'
import cx from 'classnames'
import {
  Card,
  Button,
  Statistic,
  Label,
  Icon,
  Popup
} from 'semantic-ui-react'
import ProjectIcon from './../../components/ProjectIcon'
import PercentChanges from './../../components/PercentChanges'
import { formatNumber } from '../../utils/formatting'
import { millify } from '../../utils/utils'
import './ProjectCard.css'

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
  <Statistic className={cx({
    'statistic-disabled': disabled
  })}>
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
  volumeChange24h,
  averageDevActivity,
  twitterData,
  ethSpent,
  btcBalance = 0,
  ethBalance = 0,
  marketcapUsd,
  teamTokenWallet,
  signals,
  onClick
}) => {
  const warning = signals && signals.length > 0
  return (
    <Card fluid >
      <Card.Content>
        <Card.Header>
          <div style={{display: 'flex', alignItems: 'center', justifyContent: 'space-between'}}>
            <div style={{display: 'flex', alignItems: 'center'}}>
              {name}&nbsp;<ProjectIcon name={name} />
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
        <Card.Meta>
          <Label
            size='mini'
            color={MARKET_SEGMENT_COLORS[marketSegment]} tag>
            {marketSegment || 'unknown market segment yet'}
          </Label>
        </Card.Meta>
        <Card.Description>
          {!description
            ? "We don't have any description about this project yet."
            : description}
        </Card.Description>
      </Card.Content>
      <Card.Content extra style={{position: 'relative'}}>
        {warning &&
        <Popup basic
          position='right center'
          hideOnScroll
          wide
          inverted
          trigger={
            <Label
              style={{
                position: 'absolute',
                top: '10px',
                left: '-14px'
              }}
              color='orange' ribbon>
              <Icon name='warning sign' />
            </Label>} on='click'>
          {signals[0] && signals[0].description}
        </Popup>}
        <Statistic.Group size='mini' widths='two' style={{paddingBottom: '1em'}}>
          <StatisticElement
            name='Price'
            value={priceUsd ? formatNumber(priceUsd, 'USD') : '---'}
            disabled={!priceUsd} />
          <StatisticElement
            name='Volume'
            value={volumeUsd
              ? `$${millify(parseFloat(volumeUsd))}`
              : '---'}
            disabled={!volumeUsd} />
          <StatisticElement
            name='24h Price'
            up={percentChange24h > 0}
            value={percentChange24h || '---'}
            disabled={!percentChange24h} />
          <StatisticElement
            name='24h Volume'
            up={volumeChange24h > 0}
            value={volumeChange24h || '---'}
            disabled={!volumeChange24h} />
          <StatisticElement
            name='MarketCap'
            value={marketcapUsd
              ? `$${millify(parseFloat(marketcapUsd))}`
              : '---'}
            disabled={!marketcapUsd} />
          <StatisticElement
            name='Crypto Balance'
            value={ethBalance
              ? `ETH ${millify(parseFloat(parseFloat(ethBalance).toFixed(2)))}`
              : '---'}
            disabled={!ethBalance} />
          <StatisticElement
            name='ETH Spent 30d'
            value={ethSpent
              ? `ETH ${millify(parseFloat(parseFloat(ethSpent).toFixed(2)))}`
              : '---'}
            disabled={!ethSpent} />
          <StatisticElement
            name='Dev Activity 30d'
            value={averageDevActivity ? parseFloat(averageDevActivity).toFixed(2) : '---'}
            disabled={!averageDevActivity} />
          <HiddenElements>
            <StatisticElement
              name='Twitter 30d'
              value={twitterData || '---'}
              disabled={!twitterData} />
          </HiddenElements>
        </Statistic.Group>
      </Card.Content>
      <Card.Content extra>
        <div className='ui two buttons'>
          <HiddenElements>
            <Button basic size='large' icon='star' />
          </HiddenElements>
          <Button basic size='large' onClick={onClick}>more...</Button>
        </div>
      </Card.Content>
    </Card>
  )
}

export default ProjectCard
