import React from 'react'
import './Roadmap.css'

const Roadmap = props => {
  return (
    <div className='page roadmap'>
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
            <div className='entry present'>
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
                <div className='status-row' id='low-orbit'>
                  <span className='status-item'>Develop SANbase backend architecture and wireframe UI</span>
                  <span className='status'>
                    <div className='status-percent'>100%</div>
                    <div className='status-border'>
                      <div
                        style={{width: '100%'}}
                        className='status-progress' />
                    </div>
                  </span>
                </div>
                <p><strong>Data-feeds:</strong> Bring in first round of real-time feeds:</p>
                <ul>
                  <li>
                    <div className='status-row embedded' id='crypto-projects-item'>
                      <span className='status-item'>Crypto projects with key metrics</span>
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
                    <div className='status-row embedded' id='detailed-views-item'>
                      <span className='status-item'>Detailed views of each project</span>
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
                    <div className='status-row embedded nobg'>
                      <span className='status-item'>Crypto Cash Flow:</span>
                    </div>
                    <ul>
                      <li>
                        <div className='status-row embedded' id='team-wallets-item'>
                          <span className='status-item'>Team wallets</span>
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
                        <div className='status-row embedded'>
                          <span className='status-item'>Whale wallets</span>
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
                        <div className='status-row embedded'>
                          <span className='status-item'>Exchange wallets</span>
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
                    </ul>
                  </li>
                  <li>
                    <div className='status-row embedded'>
                      <span className='status-item'>Price History</span>
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
                  <li>Market Cap and volume</li>
                  <li>More...</li>
                </ul>
                <p><strong>Signals:</strong> Develop first signals (in our slack channel):</p>
                <ul>
                  <li>
                    <div className='status-row embedded'>
                      <span className='status-item'>Price increase/decrease over the threshold</span>
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
                    <div className='status-row embedded'>
                      <span className='status-item'>When team wallet transations occur</span>
                      <span className='status'>
                        <div className='status-percent'>25%</div>
                        <div className='status-border'>
                          <div
                            style={{width: '25%'}}
                            className='status-progress' />
                        </div>
                      </span>
                    </div>
                  </li>
                  <li>When money moves from long-term token holders and whales</li>
                  <li>If token trading volumes exceed last 10 days average</li>
                  <li>Time-sensitive insights or news from the community</li>
                  <li>More...</li>
                </ul>
                <p><strong>SAN Token integration:</strong></p>
                <ul>
                  <li>
                    <div className='status-row embedded'>
                      <span className='status-item'>Authentication with SAN token</span>
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
                </ul>
                <p>
                  Experiment with SAN rewards for community engagement:
                </p>
                <ul>
                  <li>Data curation</li>
                  <li>Quality control</li>
                  <li>More...</li>
                </ul>
                <p>SANbase alpha release:</p>
                <ul>
                  <li>
                    <div className='status-row embedded'>
                      <span className='status-item'>DApp release. SAN token usage launched</span>
                      <span className='status'>
                        <div className='status-percent'>15%</div>
                        <div className='status-border'>
                          <div
                            style={{width: '15%'}}
                            className='status-progress' />
                        </div>
                      </span>
                    </div>
                  </li>
                  <li>
                    <div className='status-row embedded' id='mobile-port-item'>
                      <span className='status-item'>Port to mobile. Changed the plans. Moving to bots.</span>
                      <span className='status'>
                        <div className='status-percent'>15%</div>
                        <div className='status-border'>
                          <div
                            style={{width: '25%'}}
                            className='status-progress' />
                        </div>
                      </span>
                    </div>
                  </li>
                </ul>
              </div>
            </div>
            <div className='entry future'>
              <div className='title'>
                <h3>Medium Orbit</h3>
                <p>2018</p>
                <hr />
                <p>Business Models<br />
                  Token Economy</p>
              </div>
              <div className='body'>
                <div>
                  <p>Refine business and economic systems</p>
                  <p />
                </div>
                <div>
                  <p>Set pricing and staking levels</p>
                  <p />
                </div>
                <div>
                  <p id='open-san-api'>Open the SANbase API</p>
                  <p />
                </div>
                <p>Expand the set of data-feeds/signals:</p>
                <ul>
                  <li>Social metrics (Twitter followers, Slack activity, etc)</li>
                  <li>Crowd sentiment</li>
                  <li>Blockchain analytics</li>
                  <li>More...</li>
                </ul>
                <p>Sell first subscriptions (fiat and crypto)</p>
                <p>SANbase Beta</p>
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
}

export default Roadmap
