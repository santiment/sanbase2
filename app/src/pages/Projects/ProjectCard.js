import React from 'react'
import { Card, Statistic } from 'semantic-ui-react'
import ProjectIcon from './../../components/ProjectIcon'

// Project Name
// Market Cap
// Crypto Balance (ETH) - the current Balance column
// ETH Spent (30d) - total change in ETH balance for the last 30 days
// Dev Activity (30d) - total dev activity for the last 30 days
// Flag - signals flag. For now we only show it when Crypto Balance > Market Cap

const ProjectCard = (props) => {
  return (
    <Card fluid color='violet'>
      <Card.Content>
        <ProjectIcon name='SAN' />
        <Card.Header>
          Santiment Token
        </Card.Header>
        <Card.Meta>
          Financial
        </Card.Meta>
        <Card.Description>
          Awesome <strong>summary</strong> about this token
        </Card.Description>
      </Card.Content>
      <Card.Content extra>
        <Statistic.Group size='tiny' flated='left'>
          <Statistic >
            <Statistic.Label>Price</Statistic.Label>
            <Statistic.Value>1.0$</Statistic.Value>
          </Statistic>
          <Statistic >
            <Statistic.Label>24h</Statistic.Label>
            <Statistic.Value>+10%</Statistic.Value>
          </Statistic>
          <Statistic>
            <Statistic.Label>Dev Activity</Statistic.Label>
            <Statistic.Value>22</Statistic.Value>
          </Statistic>
          <Statistic>
            <Statistic.Label>Crypto Balance</Statistic.Label>
            <Statistic.Value>100.000$</Statistic.Value>
          </Statistic>
          <Statistic>
            <Statistic.Label>MarketCap</Statistic.Label>
            <Statistic.Value>100.000.000$</Statistic.Value>
          </Statistic>
        </Statistic.Group>
      </Card.Content>
    </Card>
  )
}

export default ProjectCard
