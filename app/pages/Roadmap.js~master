import React from 'react'
import { Helmet } from 'react-helmet'
import { getOrigin } from './../utils/utils'
import './Roadmap.css'

const StatusItemWithProgress = ({
  text = '',
  progress = 100,
  child = false
}) => (
  <li style={{ marginLeft: child ? 20 : 0 }}>
    <div className='status-row embedded' id='crypto-projects-item'>
      <span className='status-item'>{text}</span>
      <span className='status'>
        <div className='status-percent'>{progress}%</div>
        <div className='status-border'>
          <div style={{ width: `${progress}%` }} className='status-progress' />
        </div>
      </span>
    </div>
  </li>
)

const Roadmap = () => (
  <div className='page roadmap'>
    <Helmet>
      <title>Roadmap</title>
      <link rel='canonical' href={`${getOrigin()}/roadmap`} />
    </Helmet>
    <div className='page-head'>
      <h1>SANbase Roadmap</h1>
      <p>
        Please see our SANbase roadmap below. It is a living document;
        milestones may adjust.
      </p>
    </div>
    <div className='panel'>
      <div className='fadeout'>
        <div className='timeline'>
          <div className='entry past'>
            <div className='title'>
              <h3>Launch</h3>
              <p>Q1-Q2, 2017</p>
            </div>
            <div className='body'>
              <p>Generate first proofs of concept and initial funding</p>
              <ul>
                <li>Concierge MVP for crowdsourcing via community</li>
                <li>Pre-Sale</li>
                <li>Mobile alpha with charts and historical price feeds</li>
                <li>Sentiment journaling game prototype</li>
                <li>Trollbox feeds</li>
                <li>Subscription smart contract</li>
                <li>First set of strategic partnerships</li>
                <li>Whitepaper Release</li>
                <li>Crowdsale</li>
              </ul>
            </div>
          </div>
          <div className='entry past'>
            <div className='title'>
              <h3>Low Orbit</h3>
              <p>Q3-Q4, 2017</p>
              <hr />
              <p>
                Transparency
                <br />
                Product
                <br />
                Community
              </p>
            </div>
            <div className='body'>
              <ul>
                <li>Develop SanBase backend architecture</li>
                <li>UI/UX. Overview and detailed view</li>
                <li>Bring first data-feeds</li>
                <li>
                  First set of signals (delivered to the slack channel, later
                  moved to discord)
                </li>
                <li>Initial SAN token integration</li>
                <li>First experiments with SAN rewards</li>
              </ul>

              <p>Release: SanBase alpha release</p>
            </div>
          </div>
          <div className='entry future'>
            <div className='title'>
              <h3>Medium Orbit</h3>
              <p>2018</p>
              <hr />
              <p>Business</p>
              <p>Models</p>
              <p>Token</p>
              <p>Economy</p>
            </div>
            <div className='body'>
              <p>Slight pivot. Increase focus for on-chain data/analyses</p>
              <ul>
                <li>Data-feeds for all ERC-20 tokens</li>
                <StatusItemWithProgress
                  text={
                    'Daily Active Addresses (DAA), TokenAging (Burn Rate), Transaction volume'
                  }
                  progress={100}
                  child
                />
                <StatusItemWithProgress
                  text={'In/Out exchanges'}
                  progress={100}
                  child
                />
                <StatusItemWithProgress
                  text={'ETH Genesis Address Activity'}
                  progress={100}
                  child
                />
                <StatusItemWithProgress
                  text={'Price-Volume Difference Indicator'}
                  progress={100}
                  child
                />
                <StatusItemWithProgress
                  text={'Token Circulation'}
                  progress={100}
                  child
                />
                <StatusItemWithProgress
                  text={'Transaction Volume'}
                  progress={100}
                  child
                />
                <StatusItemWithProgress
                  text={'Velocity of Token'}
                  progress={100}
                  child
                />
                <StatusItemWithProgress
                  text={'Top 100 Transactions'}
                  progress={100}
                  child
                />
                <StatusItemWithProgress
                  text={'Network growth'}
                  progress={100}
                  child
                />
                <li>Data-feeds for all EOS tokens</li>
                <StatusItemWithProgress
                  text={'Actions Volume'}
                  progress={50}
                  child
                />
                <StatusItemWithProgress
                  text={'Number of Active Currencies'}
                  progress={100}
                  child
                />
                <StatusItemWithProgress
                  text={'Transaction Volume of the Most Active Currencies'}
                  progress={100}
                  child
                />
                <StatusItemWithProgress
                  text={'Transaction Volume of EOS'}
                  progress={100}
                  child
                />
                <StatusItemWithProgress
                  text={'Daily Active Addresses of EOS'}
                  progress={100}
                  child
                />
                <StatusItemWithProgress
                  text={'Gateway to include data from other blockchains'}
                  progress={90}
                />
                <StatusItemWithProgress text={'EOS'} child progress={100} />
                <StatusItemWithProgress text={'Bitcoin'} child progress={100} />
                <StatusItemWithProgress text={'XLM'} child progress={10} />
                <StatusItemWithProgress text={'ADA'} child progress={10} />
                <StatusItemWithProgress text={'TRON'} child progress={10} />
                <StatusItemWithProgress text={'VET'} child progress={10} />
                <StatusItemWithProgress text={'NEO'} child progress={10} />
                <li>Different interfaces to work with data</li>
                <StatusItemWithProgress
                  text={'API, SQL, Grafana'}
                  child
                  progress={100}
                />
                <StatusItemWithProgress
                  text={'UI Components'}
                  child
                  progress={10}
                />
                <li>Social metrics</li>
                <StatusItemWithProgress
                  text={'Topic Search'}
                  child
                  progress={100}
                />
                <StatusItemWithProgress
                  text={'Relative Social Dominance'}
                  child
                  progress={100}
                />
                <StatusItemWithProgress
                  text={'Social Volume'}
                  child
                  progress={100}
                />
                <StatusItemWithProgress
                  text={'Social Data feed'}
                  child
                  progress={100}
                />
                <StatusItemWithProgress
                  text={'Github Activity'}
                  progress={100}
                />
                <StatusItemWithProgress
                  text={
                    'Base NLP models. Allows to build more complicated AI algorithms for social data'
                  }
                  progress={100}
                />
                <StatusItemWithProgress
                  text={'Advanced AI/ML models'}
                  progress={20}
                />
                <StatusItemWithProgress
                  text={'Community “insights”'}
                  progress={100}
                />
                <StatusItemWithProgress text={'Token economy'} progress={60} />
                <li>Signals - ongoing process</li>
              </ul>
            </div>
          </div>
          <div className='entry future'>
            <div className='title'>
              <h3>High Orbit</h3>
              <p>2019</p>
              <hr />
              <p>Decentralization</p>
            </div>
            <div className='body'>
              <p>
                Product/community/network is self-sustaining, ready for general
                availability.
              </p>
              <ul>
                <li>Social/Reputation systems</li>
                <li>Self-publishing systems</li>
                <li>200+ datafeeds</li>
                <li>Functioning payment/staking/reward token economy</li>
                <li>Desktop & Mobile terminals first commercial release</li>
                <li>3rd party integrations</li>
              </ul>
            </div>
          </div>
        </div>
      </div>
    </div>
  </div>
)

export default Roadmap
