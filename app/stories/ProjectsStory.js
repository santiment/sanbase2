import React from 'react'
import { storiesOf } from '@storybook/react'
import ProjectCard from './../src/pages/Projects/ProjectCard'

const projects = [
  {
    'volumeUsd': '6067610.0',
    'ticker': 'FCT',
    'priceUsd': '24.5983',
    'percentChange24h': '5.38',
    'name': 'Factom',
    'marketcapUsd': '215114643.0',
    'marketSegment': 'Media',
    'id': '42',
    rank: 1,
    'description': null
  },
  {
    'volumeUsd': '52521500.0',
    'ticker': 'LSK',
    'priceUsd': '20.8335',
    'percentChange24h': '22.28',
    'name': 'Lisk',
    'marketcapUsd': '2455031890.0',
    'marketSegment': 'Blockchain Network',
    'id': '88',
    rank: 2,
    'description': null
  },
  {
    'volumeUsd': '8178870.0',
    'ticker': 'NXT',
    'priceUsd': '0.177701',
    'percentChange24h': '7.91',
    'name': 'Nxt',
    'marketcapUsd': '177523289.0',
    'marketSegment': 'Financial',
    rank: 3,
    'id': '53',
    'description': null
  },
  {
    'volumeUsd': '685540000.0',
    'ticker': 'EOS',
    'priceUsd': '8.1173',
    'percentChange24h': '3.84',
    'name': 'EOS',
    'marketcapUsd': '5321851061.0',
    'marketSegment': 'Blockchain Network',
    'id': '1',
    rank: 4,
    'description': null
  },
  {
    'volumeUsd': '1119680.0',
    'ticker': 'STX',
    'priceUsd': '0.440421',
    'percentChange24h': '0.07',
    'name': 'Stox',
    'marketcapUsd': '18557292.0',
    'marketSegment': null,
    'id': '20',
    rank: 5,
    'description': null
  }
]

storiesOf('Cashflow page', module)
  .add('Project card', () => (
    <div style={{padding: 20}}>
      <ProjectCard />
    </div>
  ))
  .add('Project card list', () => (
    <div style={{padding: 20}}>
      {projects.map((project, index) => (
        <ProjectCard key={index} {...project} />
      ))}
    </div>
  ))
