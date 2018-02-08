import React from 'react'
import { Card, Button, Statistic, Label } from 'semantic-ui-react'
import ProjectIcon from './../../components/ProjectIcon'
import { formatNumber } from '../../utils/formatting'
import { millify } from '../../utils/utils'

// Project Name
// Market Cap
// Crypto Balance (ETH) - the current Balance column
// ETH Spent (30d) - total change in ETH balance for the last 30 days
// Dev Activity (30d) - total dev activity for the last 30 days
// Flag - signals flag. For now we only show it when Crypto Balance > Market Cap
//

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

const ProjectCard = ({
  name,
  rank,
  ticker,
  description,
  marketSegment,
  priceUsd,
  percentChange24h,
  volumeUsd,
  githubData = null,
  btcBalance = 0,
  ethBalance = 0,
  marketcapUsd,
  teamTokenWallet
}) => {
  return (
    <Card fluid color={MARKET_SEGMENT_COLORS[marketSegment]}>
      <Card.Content>
        <Card.Header>
          <div style={{display: 'flex', alignItems: 'center', justifyContent: 'space-between'}}>
            <div style={{display: 'flex', alignItems: 'center'}}>
              <ProjectIcon name={ticker} />
              {name}
            </div>
            <small>rank: {rank}</small>
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
        <Statistic.Group size='mini' widths='two'>
          <Statistic >
            <Statistic.Label>Price</Statistic.Label>
            <Statistic.Value>{formatNumber(priceUsd, 'USD')}</Statistic.Value>
          </Statistic>
          <Statistic >
            <Statistic.Label>24h Price</Statistic.Label>
            <Statistic.Value>{percentChange24h}%</Statistic.Value>
          </Statistic>
          <Statistic>
            <Statistic.Label>Volume</Statistic.Label>
            <Statistic.Value>{millify(parseFloat(volumeUsd))}</Statistic.Value>
          </Statistic>
          <Statistic>
            <Statistic.Label>MarketCap</Statistic.Label>
            <Statistic.Value>{millify(parseFloat(marketcapUsd))}</Statistic.Value>
          </Statistic>
          {!!githubData && <Statistic>
            <Statistic.Label>Dev Activity</Statistic.Label>
            <Statistic.Value>{githubData}</Statistic.Value>
          </Statistic>}
          <Statistic>
            <Statistic.Label>Crypto Balance</Statistic.Label>
            <Statistic.Value>ETH {ethBalance}</Statistic.Value>
          </Statistic>
        </Statistic.Group>
      </Card.Content>
      <Card.Content extra>
        <div className='ui three buttons'>
          <Button basic size='large' icon='warning sign' />
          <Button basic size='large' icon='pencil' />
          <Button basic size='large' icon='star' />
        </div>
      </Card.Content>
    </Card>
  )
}

export default ProjectCard
