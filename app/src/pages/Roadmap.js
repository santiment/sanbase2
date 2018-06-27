import React from 'react'
import { Helmet } from 'react-helmet'
import { getOrigin } from './../utils/utils'
import './Roadmap.css'

const Roadmap = () => (
  <div className='page roadmap'>
    <Helmet>
      <title>SANbase: Roadmap</title>
      <link rel='canonical' href={`${getOrigin()}/roadmap`} />
    </Helmet>
    <div className='page-head'>
      <h1>SANbase Roadmap</h1>
      <p>Please see our SANbase roadmap below. It is a living document; milestones may adjust.</p>
    </div>
    <div className='panel'>
      <div className='fadeout'>
        <div className='timeline'>
          <div className='entry past'>
            <div className='title'>
              <h3>Launch</h3>
              <p>Q1-Q2, 2017</p>
              <hr />
              <p>Completed to date</p>
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
                Transparency<br />
                Product<br />
                Community
              </p>
            </div>
            <div className='body'>
              <ul>
                <li>
                  Develop SanBase backend architecture
                </li>
                <li>
                  UI/UX. Overview and detailed view
                </li>
                <li>
                  Bring first data-feeds
                </li>
                <li>
                  First set of signals (delivered to the slack channel, later moved to discord)
                </li>
                <li>
                  Initial SAN token integration
                </li>
                <li>
                  First experiments with SAN rewards
                </li>
              </ul>

              <p>Release: SanBase alpha release</p>

            </div>
          </div>
          <div className='entry future'>
            <div className='title'>
              <h3>Medium Orbit</h3>
              <p>2018</p>
              <hr />
              <p>
                Business
              </p>
              <p>
                Models
              </p>
              <p>
                Token
              </p>
              <p>
                Economy
              </p>
            </div>
            <div className='body'>
              <p>Slight pivot. Increase focus for on-chain data/analyses</p>
              <ul>
                <li>
                  Data-feeds for all ERC-20 tokens
                </li>
                <li style={{marginLeft: '20px'}}>
                  <div className='status-row embedded' id='crypto-projects-item'>
                    <span className='status-item'>Daily Active Addresses (DAA), TokenAging (Burn Rate), Transaction volume</span>
                    <span className='status'>
                      <div className='status-percent'>100%</div>
                      <div className='status-border'>
                        <div
                          style={{width: '100%'}}
                          className='status-progress' />
                      </div>
                    </span>
                  </div>
                </li>
                <li style={{marginLeft: '20px'}}>
                  <div className='status-row embedded' id='crypto-projects-item'>
                    <span className='status-item'>In/Out exchanges</span>
                    <span className='status'>
                      <div className='status-percent'>90%</div>
                      <div className='status-border'>
                        <div
                          style={{width: '90%'}}
                          className='status-progress' />
                      </div>
                    </span>
                  </div>
                </li>
                <li>
                  <div className='status-row embedded' id='crypto-projects-item'>
                    <span className='status-item'>Gateway to include data from other blockchains</span>
                    <span className='status'>
                      <div className='status-percent'>90%</div>
                      <div className='status-border'>
                        <div
                          style={{width: '90%'}}
                          className='status-progress' />
                      </div>
                    </span>
                  </div>
                </li>
                <li style={{marginLeft: '20px'}}>
                  <div className='status-row embedded' id='crypto-projects-item'>
                    <span className='status-item'>EOS</span>
                    <span className='status'>
                      <div className='status-percent'>10%</div>
                      <div className='status-border'>
                        <div
                          style={{width: '10%'}}
                          className='status-progress' />
                      </div>
                    </span>
                  </div>
                </li>
                <li style={{marginLeft: '20px'}}>
                  <div className='status-row embedded' id='crypto-projects-item'>
                    <span className='status-item'>Bitcoin</span>
                    <span className='status'>
                      <div className='status-percent'>70%</div>
                      <div className='status-border'>
                        <div
                          style={{width: '70%'}}
                          className='status-progress' />
                      </div>
                    </span>
                  </div>
                </li>
                <li>
                  <div className='status-row embedded' id='crypto-projects-item'>
                    <span className='status-item'>Different interfaces to work with data (beta)</span>
                    <span className='status'>
                      <div className='status-percent'>80%</div>
                      <div className='status-border'>
                        <div
                          style={{width: '80%'}}
                          className='status-progress' />
                      </div>
                    </span>
                  </div>
                </li>
                <li>
                  <div className='status-row embedded' id='crypto-projects-item'>
                    <span className='status-item'>Base NLP models. Allows to build more complicated AI algorithms for social data</span>
                    <span className='status'>
                      <div className='status-percent'>100%</div>
                      <div className='status-border'>
                        <div
                          style={{width: '100%'}}
                          className='status-progress' />
                      </div>
                    </span>
                  </div>
                </li>
                <li>
                  <div className='status-row embedded' id='crypto-projects-item'>
                    <span className='status-item'>Advanced AI/ML models</span>
                    <span className='status'>
                      <div className='status-percent'>10%</div>
                      <div className='status-border'>
                        <div
                          style={{width: '10%'}}
                          className='status-progress' />
                      </div>
                    </span>
                  </div>
                </li>
                <li>
                  <div className='status-row embedded' id='crypto-projects-item'>
                    <span className='status-item'>Community “insights”</span>
                    <span className='status'>
                      <div className='status-percent'>70%</div>
                      <div className='status-border'>
                        <div
                          style={{width: '70%'}}
                          className='status-progress' />
                      </div>
                    </span>
                  </div>
                </li>
                <li>
                  <div className='status-row embedded' id='crypto-projects-item'>
                    <span className='status-item'>Token economy</span>
                    <span className='status'>
                      <div className='status-percent'>50%</div>
                      <div className='status-border'>
                        <div
                          style={{width: '50%'}}
                          className='status-progress' />
                      </div>
                    </span>
                  </div>
                </li>
                <li>
                  Signals - ongoing process
                </li>
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
              <p>Product/community/network is self-sustaining, ready for general availability.</p>
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
