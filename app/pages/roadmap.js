import Head from 'next/head'
import MainHead from '../components/main-head'
import SideMenu from '../components/side-menu'
import Topbar from '../components/topbar'
import HeaderPage from '../components/header-page'

const Index = (props) => (
  <div>
    <MainHead />
    <SideMenu />
    <div className="container vert-stretch" id="main">
      <Topbar />
      <HeaderPage name="SANbase Roadmap" description="Please see our SANbase roadmap below. It is a living document; milestones may adjust."/>
      <div className="row vert-stretch">
        <div className="col-12 vert-full">
          <div className="panel vert-full">
            <div className="fadeout">
              <div className="timeline">
                <a name="goal1"></a>
                <div className="entry past">
                  <div className="title">
                    <h3>Launch</h3>
                    <p>Q1-Q2, 2017</p>
                    <hr />
                    <p>Completed to date</p>
                  </div>
                  <div className="body">
                    <p>Generate first proofs of concept and initial funding</p>
                    <ul>
                      <li>Concierge MVP for crowdsourcing via community</li>
                      <li>Pre-Sale</li>
                      <li>Mobile alpha with charts and historical price feeds</li>
                      <li>Sentiment journaling game prototype</li>
                      <li>Trollbox feeds</li>
                      <li>Subscription smart contract</li>
                      <li>First set of strategic partnerships<a name="goal2"></a></li>
                      <li>Whitepaper Release</li>
                      <li>Crowdsale</li>
                    </ul>
                  </div>
                </div>
                <div className="entry present">
                  <div className="title">
                    <h3>Low Orbit</h3>
                    <p>Q3-Q4, 2017</p>
                    <hr />
                    <p>
                      Transparency<br />
                      Product<br />
                      Community
                    </p>
                  </div>
                  <div className="body">
                    <div className="status-row" style={{'marginBottom': '10px'}}>
                      <span className="status-item">Develop SANbase backend architecture and wireframe UI</span>
                      <span className="status" style={{'width':'27%'}}>
                        <div className="status-percent">30%</div>
                        <div className="status-border">
                          <div className="status-progress" style={{'width':'30%'}}></div>
                        </div>
                      </span>
                    </div>
                    <p><strong>Data-feeds:</strong> Bring in first round of real-time feeds:</p>
                    <ul>
                      <li>
                        <div className="status-row embedded">
                          <span className="status-item">Crypto projects with key metrics</span>
                          <span className="status" style={{'width':'28.4%'}}>
                            <div className="status-percent">10%</div>
                            <div className="status-border">
                              <div className="status-progress" style={{'width':'20%'}}></div>
                            </div>
                          </span>
                        </div>
                      </li>
                      <li>
                        <div className="status-row embedded">
                          <span className="status-item">Detailed views of each project</span>
                          <span className="status" style={{'width':'28.4%'}}>
                            <div className="status-percent">10%</div>
                            <div className="status-border">
                              <div className="status-progress" style={{'width':'20%'}}></div>
                            </div>
                          </span>
                        </div>
                      </li>
                      <li>
                        <div className="status-row embedded nobg">
                          <span className="status-item">Crypto Cash Flow:</span>
                        </div>
                        <ul>
                          <li>
                            <div className="status-row embedded">
                              <span className="status-item">Team wallets</span>
                              <span className="status">
                                <div className="status-percent">80%</div>
                                <div className="status-border">
                                  <div className="status-progress" style={{'width':'80%'}}></div>
                                </div>
                              </span>
                            </div>
                          </li>
                          <li>
                            <div className="status-row embedded nobg">
                                Whale wallets
                            </div>
                          </li>
                          <li>
                            <div className="status-row embedded nobg">
                                Exchange wallets
                            </div>
                          </li>
                        </ul>
                      </li>
                      <li>Price History</li>
                      <li>Market Cap & related metrics</li>
                      <li>More...</li>
                    </ul>
                    <p><strong>Signals:</strong> Develop first signals (push notifications):</p>
                    <ul>
                      <li>When team wallet transations occur</li>
                      <li>When money moves from long-term token holders and whales</li>
                      <li>If token trading volumes exceed last 10 days average</li>
                      <li>Time-sensitive insights or news from the community</li>
                      <li>More...</li>
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
                      <li>DApp release. SAN token usage launched</li>
                      <li>
                        <div className="status-row embedded">
                          <span className="status-item">Port to mobile. Add push notifications.</span>
                          <span className="status" style={{'width':'28.4%'}}>
                            <div className="status-percent">25%</div>
                            <div className="status-border">
                              <div className="status-progress" style={{'width':'25%'}}></div>
                            </div>
                          </span>
                        </div>
                      </li>
                    </ul>
                  </div>
                </div>
                <a name="goal3"></a>
                <div className="entry future">
                  <div className="title">
                    <h3>Medium Orbit</h3>
                    <p>2018</p>
                    <hr />
                    <p>Business Models<br />
                    Token Economy</p>
                  </div>
                  <div className="body">
                    <div>
                      <p>Refine business and economic systems</p>
                      <p></p>
                    </div>
                    <div>
                      <p>Set pricing and staking levels</p>
                      <p></p>
                    </div>
                    <div>
                      <p style={{'marginBottom': '10px'}}>Open the SANbase API</p>
                      <p></p>
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
                <a name="goal4"></a>
                <div className="entry future">
                  <div className="title">
                    <h3>High Orbit</h3>
                    <p>2019</p>
                    <hr />
                    <p>Decentralization</p>
                  </div>
                  <div className="body">
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
      </div>
    </div>
  </div>
)

export default Index
