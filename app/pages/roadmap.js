import Head from 'next/head'

const Index = (props) => (
  <div>
  <Head>
  <meta charset="utf-8"/>
  <meta name="viewport" content="width=device-width, initial-scale=1, shrink-to-fit=no"/>
  <link rel="stylesheet" href="https://maxcdn.bootstrapcdn.com/bootstrap/4.0.0-alpha.6/css/bootstrap.min.css" integrity="sha384-rwoIResjU2yc3z8GV/NPeZWAv56rSmLldC3R/AZzGRnGxQQKnKkoFVhFQhNUwEyJ" crossorigin="anonymous"/>
  <link href="https://fonts.googleapis.com/icon?family=Material+Icons" rel="stylesheet"/>
  <link href="https://fonts.googleapis.com/css?family=Roboto:300,400,700" rel="stylesheet"/>
  <script src="https://use.fontawesome.com/6f993f4769.js"></script>
  <link rel="stylesheet" href="//cdn.datatables.net/1.10.15/css/jquery.dataTables.min.css" />
  <link rel="stylesheet" href="/static/cashflow/css/style_dapp_mvp1.css" />
  <script src="https://code.jquery.com/jquery-3.0.0.min.js"></script>
  <script src="https://cdnjs.cloudflare.com/ajax/libs/tether/1.4.0/js/tether.min.js" integrity="sha384-DztdAPBWPRXSA/3eYEEUWrWCy7G5KFbe8fFjk5JAIxUYHKkDx6Qin1DkWx51bBrb" crossorigin="anonymous"></script>
  <script src="https://maxcdn.bootstrapcdn.com/bootstrap/4.0.0-alpha.6/js/bootstrap.min.js" integrity="sha384-vBWWzlZJ8ea9aCX4pEW3rVHjgjt7zpkNpZk+02D9phzyeVkE+jo0ieGizqPLForn" crossorigin="anonymous"></script>
  <script src="https://www.kryogenix.org/code/browser/sorttable/sorttable.js"></script>
  <script src="https://cdn.datatables.net/1.10.15/js/jquery.dataTables.min.js"></script>
  <script src="https://cdn.datatables.net/1.10.15/js/dataTables.bootstrap4.min.js"></script>
  <script dangerouslySetInnerHTML={{ __html: `
    (function(i,s,o,g,r,a,m){i['GoogleAnalyticsObject']=r;i[r]=i[r]||function(){
            (i[r].q=i[r].q||[]).push(arguments)},i[r].l=1*new Date();a=s.createElement(o),
        m=s.getElementsByTagName(o)[0];a.async=1;a.src=g;m.parentNode.insertBefore(a,m)
    })(window,document,'script','https://www.google-analytics.com/analytics.js','ga');

    ga('create', 'UA-100571693-1', 'auto');
    ga('send', 'pageview');
   `}} />
  </Head>

  <div dangerouslySetInnerHTML={{ __html: `
    <div class="nav-side-menu">
        <div class="brand"><img src="/static/cashflow/img/logo_sanbase.png" width="115" height="22" alt="SANbase"/></div>
        <i class="fa fa-bars fa-2x toggle-btn" data-toggle="collapse" data-target="#menu-content"></i>
        <div class="menu-list">
            <ul id="menu-content" class="menu-content collapse out">
                <li>
                    <a href="#"><i class="fa fa-home fa-md"></i> Dashboard (tbd)</a>
                </li>
                <li data-toggle="collapse" data-target="#products" class="active">
                    <a href="#"><i class="fa fa-list fa-md"></i> Data-feeds </a>
                </li>
                <ul class="sub-menu collapse" id="products">

                    <li><a href="#">Projects (tbd) </a></li>
                    <li><a href="index">Cash Flow </a> </li>
                </ul>
                <li>
                    <a href="signals"><i class="fa fa-th fa-md"></i> Signals</a>
                </li>
                <li>
                    <a href="roadmap" class="active"><i class="fa fa-map fa-md"></i> Roadmap</a>
                </li>

            </ul>
        </div>
    </div>
    <div class="container vert-stretch" id="main">
        <div class="row topbar">
            <div class="col-lg-6">
                <div style="padding-top: 24px; padding-left: 16px;">
                    <i class="material-icons">search</i>
                </div>

            </div>
            <div class="col-lg-6">
                <ul class="nav-right pull-right list-unstyled">
                    <li>
                        <span style="display: inline-block; padding-top: 22px; padding-left: 24px; padding-right: 24px; font-size: 14px;">12.5 Ξ</span>
                    </li>
                    <li>
                    </li>
                </ul>
            </div>
        </div>
        <div class="row">
            <div class="col-lg-12">
                <h1>SANbase Roadmap</h1>
                <p style="margin-left: 16px;">Please see our SANbase roadmap below. It is a living document; milestones may adjust.</p>
            </div>
        </div>
        <div class="row vert-stretch">
            <div class="col-12 vert-full">
                <div class="panel vert-full">
                    <div class="fadeout">

                    <div class="timeline">
                        <a name="goal1"></a>
                        <div class="entry past">
                            <div class="title">
                                <h3>Launch</h3>
                                <p>Q1-Q2, 2017</p>
                                <hr />
                                <p>Completed to date</p>
                            </div>
                            <div class="body">
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

                        <div class="entry present">
                            <div class="title">
                                <h3>Low Orbit</h3>
                                <p>Q3-Q4, 2017</p>
                                <hr />
                                <p>Transparency<br />
                                Product<br />
                                Community</p>
                            </div>
                            <div class="body">
                                <div class="status-row" style="margin-bottom: 10px;">
                                    <span class="status-item">Develop SANbase backend architecture and wireframe UI</span>
                                    <span class="status" style="width:27%">
                                        <div class="status-percent">30%</div>
                                        <div class="status-border">
                                          <div class="status-progress" style="width:30%"></div>
                                        </div>
                                    </span>
                                </div>
                                <p><strong>Data-feeds:</strong> Bring in first round of real-time feeds:</p>

                                <ul>
                                    <li>
                                        <div class="status-row embedded">
                                            <span class="status-item">Crypto projects with key metrics</span>
                                            <span class="status" style="width:28.4%">
                                                <div class="status-percent">10%</div>
                                                <div class="status-border">
                                                  <div class="status-progress" style="width:20%"></div>
                                                </div>
                                            </span>
                                        </div>
                                    </li>
                                    <li>
                                        <div class="status-row embedded">
                                            <span class="status-item">Detailed views of each project</span>
                                            <span class="status" style="width:28.4%">
                                                <div class="status-percent">10%</div>
                                                <div class="status-border">
                                                  <div class="status-progress" style="width:20%"></div>
                                                </div>
                                            </span>
                                        </div>
                                    </li>
                                    <li>
                                        <div class="status-row embedded nobg">
                                            <span class="status-item">Crypto Cash Flow:</span>
                                        </div>
                                        <ul>
                                            <li>
                                                <div class="status-row embedded">
                                                    <span class="status-item">Team wallets</span>
                                                    <span class="status">
                                                        <div class="status-percent">80%</div>
                                                        <div class="status-border">
                                                          <div class="status-progress" style="width:80%"></div>
                                                        </div>
                                                    </span>
                                                </div>
                                            </li>
                                            <li>
                                                <div class="status-row embedded nobg">
                                                    Whale wallets
                                                </div>
                                            </li>
                                            <li>
                                                <div class="status-row embedded nobg">
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
                                <p>Experiment with SAN rewards for community engagement:
                                <ul>
                                    <li>Data curation</li>
                                    <li>Quality control</li>
                                    <li>More...</li>
                                </ul>
                                </p>
                                <p>SANbase alpha release:</p>
                                <ul>
                                    <li>DApp release. SAN token usage launched</li>
                                    <li>
                                        <div class="status-row embedded">
                                            <span class="status-item">Port to mobile. Add push notifications.</span>
                                            <span class="status" style="width:28.4%">
                                                <div class="status-percent">25%</div>
                                                <div class="status-border">
                                                  <div class="status-progress" style="width:25%"></div>
                                                </div>
                                            </span>
                                        </div>
                                    </li>
                                </ul>
                            </div>
                        </div>
                        <a name="goal3"></a>
                        <div class="entry future">
                            <div class="title">
                                <h3>Medium Orbit</h3>
                                <p>2018</p>
                                <hr />
                                <p>Business Models<br />
                                Token Economy</p>
                            </div>
                            <div class="body">
                                <div>
                                    <p>Refine business and economic systems</p>
                                    <p></p>
                                </div>
                                <div>
                                    <p>Set pricing and staking levels</p>
                                    <p></p>
                                </div>
                                <div>
                                    <p style="margin-bottom: 10px;">Open the SANbase API</p>
                                    <p></p>
                                </div>

                                <p>Expand the set of data-feeds/signals:
                                    <ul>
                                        <li>Social metrics (Twitter followers, Slack activity, etc)</li>
                                        <li>Crowd sentiment</li>
                                        <li>Blockchain analytics</li>
                                        <li>More...</li>
                                    </ul>
                                </p>
                                <p>Sell first subscriptions (fiat and crypto)</p>
                                <p>SANbase Beta</p>
                            </div>
                        </div>
                        <a name="goal4"></a>
                        <div class="entry future">
                            <div class="title">
                                <h3>High Orbit</h3>
                                <p>2019</p>
                                <hr />
                                <p>Decentralization</p>
                            </div>
                            <div class="body">
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
   `}} />
  </div>
)

export default Index
