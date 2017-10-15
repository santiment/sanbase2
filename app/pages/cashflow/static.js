import Head from 'next/head'

const Index = (props) => (
  <div>
  <Head>
    <meta charset="utf-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1, shrink-to-fit=no" />
    <link rel="stylesheet" href="https://maxcdn.bootstrapcdn.com/bootstrap/4.0.0-alpha.6/css/bootstrap.min.css" integrity="sha384-rwoIResjU2yc3z8GV/NPeZWAv56rSmLldC3R/AZzGRnGxQQKnKkoFVhFQhNUwEyJ" crossorigin="anonymous" />
    <link href="https://fonts.googleapis.com/icon?family=Material+Icons" rel="stylesheet" />
    <link href="https://fonts.googleapis.com/css?family=Source+Sans+Pro:300,400,700" rel="stylesheet" />
    <script src="https://use.fontawesome.com/6f993f4769.js"></script>
    <link rel="stylesheet" href="https://cdn.datatables.net/1.10.15/css/jquery.dataTables.min.css" />
    <link rel="stylesheet" href="https://cdn.datatables.net/responsive/2.1.1/css/responsive.dataTables.min.css" />
    <link rel="stylesheet" href="https://cdn.datatables.net/fixedheader/3.1.2/css/fixedHeader.bootstrap.min.css" />
    <link rel="stylesheet" href="/static/cashflow/css/style_dapp_mvp1.css" />
    <script src="https://code.jquery.com/jquery-3.0.0.min.js"></script>
    <script src="https://cdnjs.cloudflare.com/ajax/libs/tether/1.4.0/js/tether.min.js" integrity="sha384-DztdAPBWPRXSA/3eYEEUWrWCy7G5KFbe8fFjk5JAIxUYHKkDx6Qin1DkWx51bBrb" crossorigin="anonymous"></script>
    <script src="https://maxcdn.bootstrapcdn.com/bootstrap/4.0.0-alpha.6/js/bootstrap.min.js" integrity="sha384-vBWWzlZJ8ea9aCX4pEW3rVHjgjt7zpkNpZk+02D9phzyeVkE+jo0ieGizqPLForn" crossorigin="anonymous"></script>
    <script src="https://www.kryogenix.org/code/browser/sorttable/sorttable.js"></script>
    <script src="https://cdn.datatables.net/1.10.15/js/jquery.dataTables.min.js"></script>
    <script src="https://cdn.datatables.net/1.10.15/js/dataTables.bootstrap4.min.js"></script>
    <script src="https://cdn.datatables.net/responsive/2.1.1/js/dataTables.responsive.min.js"></script>
    <script src="https://cdn.datatables.net/responsive/2.1.1/js/responsive.bootstrap.min.js"></script>
    <script src="https://cdn.datatables.net/fixedheader/3.1.2/js/dataTables.fixedHeader.min.js"></script>
  </Head>
  <div dangerouslySetInnerHTML={{ __html: `
    <div class="nav-side-menu">
        <div class="brand"><img src="/static/cashflow/img/logo_sanbase.png" width="115" height="22" alt="SANbase"/></div>
        <i class="fa fa-bars fa-2x toggle-btn" data-toggle="collapse" data-target="#menu-content"></i>
        <div class="menu-list">
            <ul id="menu-content" class="menu-content collapse out">
                <li>
                    <a href="#">
                        <i class="fa fa-home fa-md"></i> Dashboard (tbd)
                    </a>
                </li>
                <li data-toggle="collapse" data-target="#products" class="active">
                    <a href="#" class="active"><i class="fa fa-list fa-md"></i> Data-feeds <span class="arrow"></span></a>
                </li>
                <!-- <li data-toggle="collapse" data-target="#products" class="active">
                    <a href="projects.html" class="active"><i class="fa fa-list fa-md"></i> Projects <span class="arrow"></span></a>
                </li> -->
                <ul class="sub-menu" id="products">
                    <!-- <li><a href="#">Projects</li>
                    <li><a href="#">Token Sales</a></li> -->
                    <li><a href="#">Overview </a></li>
                    <li class="active"><a href="static" class="active">Cash Flow </a> <!-- <span class="badge badge-info">2</span> --></li>
                </ul>
                <li>
                    <a href="signals"><i class="fa fa-th fa-md"></i> Signals</a>
                </li>
                <li>
                    <a href="roadmap"><i class="fa fa-map fa-md"></i> Roadmap</a>
                </li>
            </ul>
        </div>
    </div>
    <div class="container" id="main">
        <!-- <div class="row topbar">
            <div class="col-lg-6">
                <div class="input-group">
                    <span class="input-group-addon"><i class="material-icons">search</i></span>
                    <input type="text" class="form-control" placeholder="{{ 'SEARCH' | translate }}">
                    <span class="input-bar"></span>
                </div>
            </div>
            <div class="col-lg-6">
                <ul class="nav-right pull-right list-unstyled">
                    <li>
                        <span style="display: inline-block; padding-top: 22px; font-size: 14px;">12.5 Ξ</span>
                    </li>
                    <li>
                        <md-select placeholder="brighteye" style="margin: 16px 22px 0 22px; z-index: 1111;">
                            <md-option>brighteye</md-option>
                            <md-option>testacct</md-option>
                            <md-option>stash</md-option>
                    </li>
                </ul>
            </div>
        </div> -->
        <div class="row">
            <div class="col-lg-3">
                <h1>Cash Flow</h1>

            </div>
            <div class="col-lg-9 community-actions">
                <span class="legal">brought to you by <a href="https://santiment.net" target="_blank">Santiment</a>
                <br />
                    NOTE: This app is a prototype. We give no guarantee data is correct as we are in active development.</span>
                <!-- <br />
                <span class="legal"><i class="fa fa-question-circle-o"></i> Automated data not available. <a href="#">Community help locating wallet is welcome!</a></span> -->

                <!-- <a class="btn-secondary" href="#"><i class="fa fa-pencil"></i></a> -->
                <!-- <a class="btn-primary" href="#">Supply ICO Wallet</a> -->
                <!-- <select style="width: 100px; height: 40px;">
                    <option>BTC</option>
                    <option selected>ETH</option>
                    <option>LTC</option>
                </select> -->
            </div>
        </div>
        <div class="row">
            <div class="col-12">
                <div class="panel">
                    <div class="sortable">
                        <!-- <table id="projects" class="table table-condensed table-hover" cellspacing="0" width="100%">
                            <thead>
                            <tr>
                                <th>Project</th>
                                <th>Market Cap</th>
                                <th>Balance (USD/ETH)</th>
                                <th>Last Outgoing TX</th>
                                <th>ETH Sent</th>
                            </tr>
                            </thead>
                            <tbody class='whaletable'>
                            <tr>
                                <td><img src="/static/cashflow/img/projects/aeternity.png" /> Aeternity (AE)</td>
                                <td class="marketcap"></td>
                                <td class="address-link">$0<br /><a class="address" href=""><i class="fa fa-external-link"></i> Ξ0</td>
                                <td>No transfers yet</td>
                                <td>0</td>
                            </tr>
                            <tr>
                                <td><img src="/static/cashflow/img/projects/aragon.png" /> Aragon (ANT)</td>
                                <td class="marketcap">$64,692,299</td>
                                <td class="address-link">$59,660,502<br /><a class="address" href="https://etherscan.io/address/0xcafe1a77e84698c83ca8931f54a755176ef75f2c"><i class="fa fa-external-link"></i> Ξ268,741</a></td>
                                <td>No transfers yet</td>
                                <td>0</td>
                            </tr>
                            <tr>
                                <td><img src="/static/cashflow/img/projects/augur.png" /> Augur (REP)</td>
                                <td class="marketcap">$191,477,000</td>
                                <td class="address-link">$136,030<br /><a class="address" href="https://etherscan.io/address/0xE28e72FCf78647ADCe1F1252F240bbfaebD63BcC"><i class="fa fa-external-link"></i> Ξ613</a></td>
                                <td>No transfers yet</td>
                                <td>0</td>
                            </tr>
                            <tr>
                                <td><img src="/static/cashflow/img/projects/bancor.png" /> Bancor (BNT)</td>
                                <td class="marketcap">$81,886,195</td>
                                <td class="address-link">$0<br /><a class="address" href=""><i class="fa fa-external-link"></i> Ξ0</a></td>
                                <td>No transfers yet</td>
                                <td>0</td>
                            </tr>
                            <tr>
                                <td><img src="/static/cashflow/img/projects/basic-attention-token.png" /> Basic Attention Token (BAT)</td>
                                <td class="marketcap">$140,697,000</td>
                                <td class="address-link">$0<br /><a class="address" href=""><i class="fa fa-external-link"></i> Ξ0</a></td>
                                <td>No transfers yet</td>
                                <td>0</td>
                            </tr>
                            <tr>
                                <td>Blockchain Capital (BNT)</td>
                                <td class="marketcap"></td>
                                <td class="address-link">$0<br /><a class="address" href=""><i class="fa fa-external-link"></i> Ξ0</a></td>
                                <td>No transfers yet</td>
                                <td>0</td>
                            </tr>
                            <tr>
                                <td><img src="/static/cashflow/img/projects/chronobank.png" /> Chronobank (TIME)</td>
                                <td class="marketcap">$12,789,132</td>
                                <td class="address-link">$0<br /><a class="address" href=""><i class="fa fa-external-link"></i> Ξ0</a></td>
                                <td>No transfers yet</td>
                                <td>0</td>
                            </tr>
                            <tr>
                                <td><img src="/static/cashflow/img/projects/cofound-it.png" /> Cofound.it (CFI)</td>
                                <td class="marketcap">$12,860,750</td>
                                <td class="address-link">$0<br /><a class="address" href=""><i class="fa fa-external-link"></i> Ξ0</a></td>
                                <td>No transfers yet</td>
                                <td>0</td>
                            </tr>
                            <tr>
                                <td>Contingency</td>
                                <td class="marketcap"></td>
                                <td class="address-link">$4,157,612<br /><a class="address" href=""><i class="fa fa-external-link"></i> Ξ18,728</a></td>
                                <td>No transfers yet</td>
                                <td>0</td>
                            </tr>
                            <tr>
                                <td>Cosmos</td>
                                <td class="marketcap"></td>
                                <td class="address-link">$4,157,612<br /><a class="address" href=""><i class="fa fa-external-link"></i> Ξ18,728</a></td>
                                <td>No transfers yet</td>
                                <td>0</td>
                            </tr>
                            <tr>
                                <td><img src="/static/cashflow/img/projects/digix-logo.png" /> DigixDAO (DGX)</td>
                                <td class="marketcap">$140,659,600</td>
                                <td class="address-link">$10,402,504<br /><a class="address" href="https://etherscan.io/address/0xf0160428a8552ac9bb7e050d90eeade4ddd52843"><i class="fa fa-external-link"></i> Ξ46,648</a></td>
                                <td>No transfers yet</td>
                                <td>0</td>
                            </tr>
                            <tr>
                                <td><img src="/static/cashflow/img/projects/edgeless.png" /> Edgeless (EDG)</td>
                                <td class="marketcap">$38,110,008</td>
                                <td class="address-link">$0<br /><a class="address" href=""><i class="fa fa-external-link"></i> Ξ0</a></td>
                                <td>No transfers yet</td>
                                <td>0</td>
                            </tr>
                            <tr>
                                <td><img src="/static/cashflow/img/projects/eos_28.png" /> EOS (EOS)</td>
                                <td class="marketcap">$468,910,471</td>
                                <td class="address-link">$78,474,558<br /><a class="address" href="https://etherscan.io/address/0xa72dc46ce562f20940267f8deb02746e242540ed"><i class="fa fa-external-link"></i> Ξ351,904</a></td>
                                <td>2017-07-28</td>
                                <td>3900</td>
                            </tr>
                            <tr>
                                <td><img src="/static/cashflow/img/projects/etheroll.png" /> Etheroll (DICE)</td>
                                <td class="marketcap">$31,708,459</td>
                                <td class="address-link">$3,957,135<br /><a class="address" href=""><i class="fa fa-external-link"></i> Ξ17,745</a></td>
                                <td>No transfers yet</td>
                                <td>0</td>
                            </tr>
                            <tr>
                                <td><img src="/static/cashflow/img/projects/firstblood.png" /> FirstBlood (1ST)</td>
                                <td class="marketcap">$892</td>
                                <td class="address-link">$8.92<br /><a class="address" href="https://etherscan.io/address/0xAf30D2a7E90d7DC361c8C4585e9BB7D2F6f15bc7"><i class="fa fa-external-link"></i> Ξ0.04</a></td>
                                <td>No transfers yet</td>
                                <td>0</td>
                            </tr>
                            <tr>
                                <td><img src="/static/cashflow/img/projects/gnosis-gno.png" /> Gnosis (GNO)</td>
                                <td class="marketcap">$219,657,663</td>
                                <td class="address-link">$0<br /><a class="address" href=""><i class="fa fa-external-link"></i> Ξ0</a></td>
                                <td>No transfers yet</td>
                                <td>0</td>
                            </tr>
                            <tr>
                                <td><img src="/static/cashflow/img/projects/golem-network-tokens.png" /> Golem (GNT)</td>
                                <td class="marketcap">$248,632,562</td>
                                <td class="address-link">$0<br /><a class="address" href=""><i class="fa fa-external-link"></i> Ξ0</a></td>
                                <td>No transfers yet</td>
                                <td>0</td>
                            </tr>
                            <tr>
                                <td><img src="/static/cashflow/img/projects/humaniq.png" /> Humaniq (HMQ)</td>
                                <td class="marketcap">$25,268,470</td>
                                <td class="address-link">$0<br /><a class="address" href=""><i class="fa fa-external-link"></i> Ξ0</a></td>
                                <td>No transfers yet</td>
                                <td>0</td>
                            </tr>
                            <tr>
                                <td><img src="/static/cashflow/img/projects/ICONOMI.png" /> Iconomi (ICN)</td>
                                <td class="marketcap">$270,331,346</td>
                                <td class="address-link">$36,710,142<br /><a class="address" href="https://etherscan.io/address/0x154Af3E01eC56Bc55fD585622E33E3dfb8a248d8"><i class="fa fa-external-link"></i> Ξ164,619</a></td>
                                <td>No transfers yet</td>
                                <td>0</td>
                            </tr>
                            <tr>
                                <td><img src="/static/cashflow/img/projects/rlc.png" /> iEx.ec (RLC)</td>
                                <td class="marketcap">$32,773,974</td>
                                <td class="address-link">$0<br /><a class="address" href=""><i class="fa fa-external-link"></i> Ξ0</a></td>
                                <td>No transfers yet</td>
                                <td>0</td>
                            </tr>
                            <tr>
                                <td><img src="/static/cashflow/img/projects/lunyr.png" /> Lunyr (LUN)</td>
                                <td class="marketcap">$7,666,143</td>
                                <td class="address-link">$0<br /><a class="address" href=""><i class="fa fa-external-link"></i> Ξ0</a></td>
                                <td>No transfers yet</td>
                                <td>0</td>
                            </tr>
                            <tr>
                                <td><img src="/static/cashflow/img/projects/guppy.png" /> Matchpool (GUP)</td>
                                <td class="marketcap">$9,389,325</td>
                                <td class="address-link">$0<br /><a class="address" href=""><i class="fa fa-external-link"></i> Ξ0</a></td>
                                <td>No transfers yet</td>
                                <td>0</td>
                            </tr>
                            <tr>
                                <td><img src="/static/cashflow/img/projects/melon.png" /> Melonport (MLN)</td>
                                <td class="marketcap">$31,591,077</td>
                                <td class="address-link">$0<br /><a class="address" href=""><i class="fa fa-external-link"></i> Ξ0</a></td>
                                <td>No transfers yet</td>
                                <td>0</td>
                            </tr>
                            <tr>
                                <td><img src="/static/cashflow/img/projects/mysterium.png" /> Mysterium (MYST)</td>
                                <td class="marketcap">$24,921,609</td>
                                <td class="address-link">$0<br /><a class="address" href=""><i class="fa fa-external-link"></i> Ξ0</a></td>
                                <td>No transfers yet</td>
                                <td>0</td>
                            </tr>
                            <tr>
                                <td><img src="/static/cashflow/img/projects/patientory.png" /> Patientory (PTOY)</td>
                                <td class="marketcap">$15,816,290</td>
                                <td class="address-link">$0<br /><a class="address" href=""><i class="fa fa-external-link"></i> Ξ0</a></td>
                                <td>No transfers yet</td>
                                <td>0</td>
                            </tr>
                            <tr>
                                <td><img src="/static/cashflow/img/projects/Pluton.png" /> Pluton (PLU)</td>
                                <td class="marketcap">$11,019,139</td>
                                <td class="address-link">$0<br /><a class="address" href="https://etherscan.io/address/0xa2d4035389aae620e36bd828144b2015564c2702"><i class="fa fa-external-link"></i> Ξ0</a></td>
                                <td>No transfers yet</td>
                                <td>0</td>
                            </tr>
                            <tr>
                                <td><img src="/static/cashflow/img/projects/populous.png" /> Populous (PPT)</td>
                                <td class="marketcap">$147,929,888</td>
                                <td class="address-link">$0<br /><a class="address" href=""><i class="fa fa-external-link"></i> Ξ0</a></td>
                                <td>No transfers yet</td>
                                <td>0</td>
                            </tr>
                            <tr>
                                <td><img src="/static/cashflow/img/projects/qtum.png" /> Qtum (QTUM)</td>
                                <td class="marketcap">$474,672,700</td>
                                <td class="address-link">$0<br /><a class="address" href=""><i class="fa fa-external-link"></i> Ξ0</a></td>
                                <td>No transfers yet</td>
                                <td>0</td>
                            </tr>
                            <tr>
                                <td><img src="/static/cashflow/img/projects/san_28.png" /> Santiment (SAN)</td>
                                <td class="marketcap">$12,640,715</td>
                                <td class="address-link">$9,035,223<br /><a class="address" href="https://etherscan.io/address/0x6dd5a9f47cfbc44c04a0a4452f0ba792ebfbcc9a"><i class="fa fa-external-link"></i> Ξ40,516</a></td>
                                <td>2017-07-13</td>
                                <td>0</td>
                            </tr>
                            <tr>
                                <td><img src="/static/cashflow/img/projects/sngls.png" /> SingularDTV (SNGLS)</td>
                                <td class="marketcap">$83,296,800</td>
                                <td class="address-link">$0<br /><a class="address" href="https://etherscan.io/address/0xbdf5c4f1c1a9d7335a6a68d9aa011d5f40cf5520"><i class="fa fa-external-link"></i> Ξ0</a></td>
                                <td>No transfers yet</td>
                                <td>0</td>
                            </tr>
                            <tr>
                                <td><img src="/static/cashflow/img/projects/status.png" /> Status (SNT)</td>
                                <td class="marketcap">$195,889,722</td>
                                <td class="address-link">$66,578,244<br /><a class="address" href="https://etherscan.io/address/0xa646e29877d52b9e2de457eca09c724ff16d0a2b"><i class="fa fa-external-link"></i> Ξ298,557</a></td>
                                <td>No transfers yet</td>
                                <td>0</td>
                            </tr>
                            <tr>
                                <td><img src="/static/cashflow/img/projects/storj.png" /> StorJ (STORJ)</td>
                                <td class="marketcap">$29,734,042</td>
                                <td class="address-link">$0<br /><a class="address" href=""><i class="fa fa-external-link"></i> Ξ0</a></td>
                                <td>No transfers yet</td>
                                <td>0</td>
                            </tr>
                            <tr>
                                <td><img src="/static/cashflow/img/projects/SwarmCity.png" /> Swarm City (SWT)</td>
                                <td class="marketcap">$9,040,966</td>
                                <td class="address-link">$0<br /><a class="address" href="https://etherscan.io/address/0xB9e7F8568e08d5659f5D29C4997173d84CdF2607"><i class="fa fa-external-link"></i> Ξ0</a></td>
                                <td>No transfers yet</td>
                                <td>0</td>
                            </tr>
                            <tr>
                                <td><img src="/static/cashflow/img/projects/taas.png" /> TaaS (TAAS)</td>
                                <td class="marketcap">$23,107,272</td>
                                <td class="address-link">$3,038,152<br /><a class="address" href=""><i class="fa fa-external-link"></i> Ξ13,624</a></td>
                                <td>No transfers yet</td>
                                <td>0</td>
                            </tr>
                            <tr>
                                <td><img src="/static/cashflow/img/projects/tenx.png" /> TenX (PAY)</td>
                                <td class="marketcap">$149,850,924</td>
                                <td class="address-link">$0<br /><a class="address" href=""><i class="fa fa-external-link"></i> Ξ0</a></td>
                                <td>No transfers yet</td>
                                <td>0</td>
                            </tr>
                            <tr>
                                <td>Tezos (TEZ)</td>
                                <td class="marketcap"></td>
                                <td class="address-link">$0<br /><a class="address" href=""><i class="fa fa-external-link"></i> Ξ0</a></td>
                                <td>No transfers yet</td>
                                <td>0</td>
                            </tr>
                            <tr>
                                <td><img src="/static/cashflow/img/projects/tokencard.png" /> Tokencard (TKN)</td>
                                <td class="marketcap">$17,130,922 </td>
                                <td class="address-link">$9,842<br /><a class="address" href=""><i class="fa fa-external-link"></i> Ξ44.13</a></td>
                                <td>No transfers yet</td>
                                <td>0</td>
                            </tr>
                            <tr>
                                <td><img src="/static/cashflow/img/projects/trust.png" /> WeTrust (TRST)</td>
                                <td class="marketcap">$15,318,877</td>
                                <td class="address-link">$0<br /><a class="address" href=""><i class="fa fa-external-link"></i> Ξ0</a></td>
                                <td>No transfers yet</td>
                                <td>0</td>
                            </tr>
                            <tr>
                                <td><img src="/static/cashflow/img/projects/wings.png" /> Wings (WINGS)</td>
                                <td class="marketcap">$39,061,071</td>
                                <td class="address-link">$0<br /><a class="address" href=""><i class="fa fa-external-link"></i> Ξ0</a></td>
                                <td>No transfers yet</td>
                                <td>0</td>
                            </tr>
                            </tbody>
                        </table> -->
                        <!-- <table id="projects" class="table table-condensed table-hover" cellspacing="0" width="100%">
                            <thead>
                            <tr>
                                <th>Project</th>
                                <th>Market Cap</th>
                                <th>Balance (USD/ETH)</th>
                                <th>Last Outgoing TX</th>
                                <th>ETH Sent</th>
                            </tr>
                            </thead>
                            <tbody class='whaletable'>
                            <tr>
                                <td><img src="/static/cashflow/img/aeternity.png" /> Aeternity (AE)</td>
                                <td class="marketcap"></td>
                                <td class="address-link"><span style="margin-right: 20px">$0</span><br /><a class="address" href="">Ξ0 <i class="fa fa-external-link"></i></td>
                                <td>No transfers yet</td>
                                <td>0</td>
                            </tr>
                            <tr>
                                <td><img src="/static/cashflow/img/aragon.png" /> Aragon (ANT)</td>
                                <td class="marketcap">$64,692,299</td>
                                <td class="address-link"><span style="margin-right: 20px">$59,660,502</span><br /><a class="address" href="">Ξ268,741 <i class="fa fa-external-link"></i></a></td>
                                <td>No transfers yet</td>
                                <td>0</td>
                            </tr>
                            <tr>
                                <td><img src="/static/cashflow/img/augur.png" /> Augur (REP)</td>
                                <td class="marketcap">$191,477,000</td>
                                <td class="address-link"><span style="margin-right: 20px">$136,030</span></span><br /><a class="address" href="">Ξ613 <i class="fa fa-external-link"></i> </a></td>
                                <td>No transfers yet</td>
                                <td>0</td>
                            </tr>
                            <tr>
                                <td><img src="/static/cashflow/img/bancor.png" /> Bancor (BNT)</td>
                                <td class="marketcap">$81,886,195</td>
                                <td class="address-link"><span style="margin-right: 20px">$0</span></span><br /><a class="address" href="">Ξ0 <i class="fa fa-external-link"></i></a></td>
                                <td>No transfers yet</td>
                                <td>0</td>
                            </tr>
                            <tr>
                                <td><img src="/static/cashflow/img/basic-attention-token.png" /> Basic Attention Token (BAT)</td>
                                <td class="marketcap">$140,697,000</td>
                                <td class="address-link"><span style="margin-right: 20px">$0</span><br /><a class="address" href="">Ξ0 <i class="fa fa-external-link"></i></a></td>
                                <td>No transfers yet</td>
                                <td>0</td>
                            </tr>
                            <tr>
                                <td>Blockchain Capital (BNT)</td>
                                <td class="marketcap"></td>
                                <td class="address-link"><span style="margin-right: 20px">$0</span><br /><a class="address" href="">Ξ0 <i class="fa fa-external-link"></i></a></td>
                                <td>No transfers yet</td>
                                <td>0</td>
                            </tr>
                            <tr>
                                <td><img src="/static/cashflow/img/chronobank.png" /> Chronobank (TIME)</td>
                                <td class="marketcap">$12,789,132</td>
                                <td class="address-link"><span style="margin-right: 20px">$0</span><br /><a class="address" href="">Ξ0 <i class="fa fa-external-link"></i></a></td>
                                <td>No transfers yet</td>
                                <td>0</td>
                            </tr>
                            <tr>
                                <td><img src="/static/cashflow/img/cofound-it.png" /> Cofound.it (CFI)</td>
                                <td class="marketcap">$12,860,750</td>
                                <td class="address-link"><span style="margin-right: 20px">$0</span><br /><a class="address" href="">Ξ0 <i class="fa fa-external-link"></i></a></td>
                                <td>No transfers yet</td>
                                <td>0</td>
                            </tr>
                            <tr>
                                <td>Contingency</td>
                                <td class="marketcap"></td>
                                <td class="address-link"><span style="margin-right: 20px">$4,157,612</span><br /><a class="address" href="">Ξ18,728 <i class="fa fa-external-link"></i></a></td>
                                <td>No transfers yet</td>
                                <td>0</td>
                            </tr>
                            <tr>
                                <td>Cosmos</td>
                                <td class="marketcap"></td>
                                <td class="address-link"><span style="margin-right: 20px">$4,157,612</span><br /><a class="address" href="">Ξ18,728 <i class="fa fa-external-link"></i></a></td>
                                <td>No transfers yet</td>
                                <td>0</td>
                            </tr>
                            <tr>
                                <td><img src="/static/cashflow/img/digixdao.png" /> DigixDAO (DGX)</td>
                                <td class="marketcap">$140,659,600</td>
                                <td class="address-link"><span style="margin-right: 20px">$10,402,504</span><br /><a class="address" href="">Ξ46,648 <i class="fa fa-external-link"></i></a></td>
                                <td>No transfers yet</td>
                                <td>0</td>
                            </tr>
                            <tr>
                                <td><img src="/static/cashflow/img/edgeless.png" /> Edgeless (EDG)</td>
                                <td class="marketcap">$38,110,008</td>
                                <td class="address-link"><span style="margin-right: 20px">$0</span><br /><a class="address" href="">Ξ0 <i class="fa fa-external-link"></i></a></td>
                                <td>No transfers yet</td>
                                <td>0</td>
                            </tr>
                            <tr>
                                <td><img src="/static/cashflow/img/eos.png" /> EOS (EOS)</td>
                                <td class="marketcap">$468,910,471</td>
                                <td class="address-link"><span style="margin-right: 20px">$78,474,558</span><br /><a class="address" href="">Ξ351,904 <i class="fa fa-external-link"></i></a></td>
                                <td>2017-07-28</td>
                                <td>3900</td>
                            </tr>
                            <tr>
                                <td><img src="/static/cashflow/img/etheroll.png" /> Etheroll (DICE)</td>
                                <td class="marketcap">$31,708,459</td>
                                <td class="address-link"><span style="margin-right: 20px">$3,957,135</span><br /><a class="address" href="">Ξ17,745 <i class="fa fa-external-link"></i></a></td>
                                <td>No transfers yet</td>
                                <td>0</td>
                            </tr>
                            <tr>
                                <td><img src="/static/cashflow/img/firstblood.png" /> FirstBlood (1ST)</td>
                                <td class="marketcap">$892</td>
                                <td class="address-link"><span style="margin-right: 20px">$8.92</span><br /><a class="address" href="">Ξ0.04 <i class="fa fa-external-link"></i></a></td>
                                <td>No transfers yet</td>
                                <td>0</td>
                            </tr>
                            <tr>
                                <td><img src="/static/cashflow/img/gnosis-gno.png" /> Gnosis (GNO)</td>
                                <td class="marketcap">$219,657,663</td>
                                <td class="address-link"><span style="margin-right: 20px">$0</span><br /><a class="address" href="">Ξ0 <i class="fa fa-external-link"></i></a></td>
                                <td>No transfers yet</td>
                                <td>0</td>
                            </tr>
                            <tr>
                                <td><img src="/static/cashflow/img/golem-network-tokens.png" /> Golem (GNT)</td>
                                <td class="marketcap">$248,632,562</td>
                                <td class="address-link"><span style="margin-right: 20px">$0</span><br /><a class="address" href="">Ξ0 <i class="fa fa-external-link"></i></a></td>
                                <td>No transfers yet</td>
                                <td>0</td>
                            </tr>
                            <tr>
                                <td><img src="/static/cashflow/img/humaniq.png" /> Humaniq (HMQ)</td>
                                <td class="marketcap">$25,268,470</td>
                                <td class="address-link"><span style="margin-right: 20px">$0</span><br /><a class="address" href="">Ξ0 <i class="fa fa-external-link"></i></a></td>
                                <td>No transfers yet</td>
                                <td>0</td>
                            </tr>
                            <tr>
                                <td><img src="/static/cashflow/img/ICONOMI.png" /> Iconomi (ICN)</td>
                                <td class="marketcap">$270,331,346</td>
                                <td class="address-link"><span style="margin-right: 20px">$36,710,142</span><br /><a class="address" href="">Ξ164,619 <i class="fa fa-external-link"></i></a></td>
                                <td>No transfers yet</td>
                                <td>0</td>
                            </tr>
                            <tr>
                                <td><img src="/static/cashflow/img/rlc.png" /> iEx.ec (RLC)</td>
                                <td class="marketcap">$32,773,974</td>
                                <td class="address-link"><span style="margin-right: 20px">$0</span><br /><a class="address" href="">Ξ0 <i class="fa fa-external-link"></i></a></td>
                                <td>No transfers yet</td>
                                <td>0</td>
                            </tr>
                            <tr>
                                <td><img src="/static/cashflow/img/lunyr.png" /> Lunyr (LUN)</td>
                                <td class="marketcap">$7,666,143</td>
                                <td class="address-link"><span style="margin-right: 20px">$0</span><br /><a class="address" href="">Ξ0 <i class="fa fa-external-link"></i></a></td>
                                <td>No transfers yet</td>
                                <td>0</td>
                            </tr>
                            <tr>
                                <td><img src="/static/cashflow/img/guppy.png" /> Matchpool (GUP)</td>
                                <td class="marketcap">$9,389,325</td>
                                <td class="address-link"><span style="margin-right: 20px">$0</span><br /><a class="address" href="">Ξ0 <i class="fa fa-external-link"></i></a></td>
                                <td>No transfers yet</td>
                                <td>0</td>
                            </tr>
                            <tr>
                                <td><img src="/static/cashflow/img/melon.png" /> Melonport (MLN)</td>
                                <td class="marketcap">$31,591,077</td>
                                <td class="address-link"><span style="margin-right: 20px">$0</span><br /><a class="address" href="">Ξ0 <i class="fa fa-external-link"></i></a></td>
                                <td>No transfers yet</td>
                                <td>0</td>
                            </tr>
                            <tr>
                                <td><img src="/static/cashflow/img/mysterium.png" /> Mysterium (MYST)</td>
                                <td class="marketcap">$24,921,609</td>
                                <td class="address-link"><span style="margin-right: 20px">$0</span><br /><a class="address" href="">Ξ0 <i class="fa fa-external-link"></i></a></td>
                                <td>No transfers yet</td>
                                <td>0</td>
                            </tr>
                            <tr>
                                <td><img src="/static/cashflow/img/patientory.png" /> Patientory (PTOY)</td>
                                <td class="marketcap">$15,816,290</td>
                                <td class="address-link"><span style="margin-right: 20px">$0</span><br /><a class="address" href="">Ξ0 <i class="fa fa-external-link"></i></a></td>
                                <td>No transfers yet</td>
                                <td>0</td>
                            </tr>
                            <tr>
                                <td><img src="/static/cashflow/img/Pluton.png" /> Pluton (PLU)</td>
                                <td class="marketcap">$11,019,139</td>
                                <td class="address-link"><span style="margin-right: 20px">$0</span><br /><a class="address" href="">Ξ0 <i class="fa fa-external-link"></i></a></td>
                                <td>No transfers yet</td>
                                <td>0</td>
                            </tr>
                            <tr>
                                <td><img src="/static/cashflow/img/populous.png" /> Populous (PPT)</td>
                                <td class="marketcap">$147,929,888</td>
                                <td class="address-link"><span style="margin-right: 20px">$0</span><br /><a class="address" href="">Ξ0 <i class="fa fa-external-link"></i></a></td>
                                <td>No transfers yet</td>
                                <td>0</td>
                            </tr>
                            <tr>
                                <td><img src="/static/cashflow/img/qtum.png" /> Qtum (QTUM)</td>
                                <td class="marketcap">$474,672,700</td>
                                <td class="address-link"><span style="margin-right: 20px">$0</span><br /><a class="address" href="">Ξ0 <i class="fa fa-external-link"></i></a></td>
                                <td>No transfers yet</td>
                                <td>0</td>
                            </tr>
                            <tr>
                                <td><img src="/static/cashflow/img/san_28.png" /> Santiment (SAN)</td>
                                <td class="marketcap">$12,640,715</td>
                                <td class="address-link"><span style="margin-right: 20px">$9,035,223</span><br /><a class="address" href="">Ξ40,516 <i class="fa fa-external-link"></i></a></td>
                                <td>2017-07-13</td>
                                <td>0</td>
                            </tr>
                            <tr>
                                <td><img src="/static/cashflow/img/sngls.png" /> SingularDTV (SNGLS)</td>
                                <td class="marketcap">$83,296,800</td>
                                <td class="address-link"><span style="margin-right: 20px">$0</span><br /><a class="address" href="">Ξ0 <i class="fa fa-external-link"></i></a></td>
                                <td>No transfers yet</td>
                                <td>0</td>
                            </tr>
                            <tr>
                                <td><img src="/static/cashflow/img/status.png" /> Status (SNT)</td>
                                <td class="marketcap">$195,889,722</td>
                                <td class="address-link"><span style="margin-right: 20px">$66,578,244</span><br /><a class="address" href="">Ξ298,557 <i class="fa fa-external-link"></i></a></td>
                                <td>No transfers yet</td>
                                <td>0</td>
                            </tr>
                            <tr>
                                <td><img src="/static/cashflow/img/storj.png" /> StorJ (STORJ)</td>
                                <td class="marketcap">$29,734,042</td>
                                <td class="address-link"><span style="margin-right: 20px">$0</span><br /><a class="address" href="">Ξ0 <i class="fa fa-external-link"></i></a></td>
                                <td>No transfers yet</td>
                                <td>0</td>
                            </tr>
                            <tr>
                                <td><img src="/static/cashflow/img/SwarmCity.png" /> Swarm City (SWT)</td>
                                <td class="marketcap">$9,040,966</td>
                                <td class="address-link"><span style="margin-right: 20px">$0</span><br /><a class="address" href="">Ξ0 <i class="fa fa-external-link"></i></a></td>
                                <td>No transfers yet</td>
                                <td>0</td>
                            </tr>
                            <tr>
                                <td><img src="/static/cashflow/img/taas.png" /> TaaS (TAAS)</td>
                                <td class="marketcap">$23,107,272</td>
                                <td class="address-link"><span style="margin-right: 20px">$3,038,152</span><br /><a class="address" href="">Ξ13,624 <i class="fa fa-external-link"></i></a></td>
                                <td>No transfers yet</td>
                                <td>0</td>
                            </tr>
                            <tr>
                                <td><img src="/static/cashflow/img/tenx.png" /> TenX (PAY)</td>
                                <td class="marketcap">$149,850,924</td>
                                <td class="address-link"><span style="margin-right: 20px">$0</span><br /><a class="address" href="">Ξ0 <i class="fa fa-external-link"></i></a></td>
                                <td>No transfers yet</td>
                                <td>0</td>
                            </tr>
                            <tr>
                                <td>Tezos (TEZ)</td>
                                <td class="marketcap"></td>
                                <td class="address-link"><span style="margin-right: 20px">$0</span><br /><a class="address" href="">Ξ0 <i class="fa fa-external-link"></i></a></td>
                                <td>No transfers yet</td>
                                <td>0</td>
                            </tr>
                            <tr>
                                <td><img src="/static/cashflow/img/tokencard.png" /> Tokencard (TKN)</td>
                                <td class="marketcap">$17,130,922 </td>
                                <td class="address-link"><span style="margin-right: 20px">$9,842</span><br /><a class="address" href="">Ξ44.13 <i class="fa fa-external-link"></i></a></td>
                                <td>No transfers yet</td>
                                <td>0</td>
                            </tr>
                            <tr>
                                <td><img src="/static/cashflow/img/trust.png" /> WeTrust (TRST)</td>
                                <td class="marketcap">$15,318,877</td>
                                <td class="address-link"><span style="margin-right: 20px">$0</span><br /><a class="address" href="">Ξ0 <i class="fa fa-external-link"></i></a></td>
                                <td>No transfers yet</td>
                                <td>0</td>
                            </tr>
                            <tr>
                                <td><img src="/static/cashflow/img/wings.png" /> Wings (WINGS)</td>
                                <td class="marketcap">$39,061,071</td>
                                <td class="address-link"><span style="margin-right: 20px">$0</span><br /><a class="address" href="">Ξ0 <i class="fa fa-external-link"></i></a></td>
                                <td>No transfers yet</td>
                                <td>0</td>
                            </tr>
                            </tbody>
                        </table> -->
                        <!-- <table id="projects" class="table table-condensed table-hover" cellspacing="0" width="100%">
                            <thead>
                            <tr>
                                <th>Project</th>
                                <th>Market Cap</th>
                                <th>Balance (USD/ETH)</th>
                                <th>Last Outgoing TX</th>
                                <th>ETH Sent</th>
                            </tr>
                            </thead>
                            <tbody class='whaletable'>
                            <tr>
                                <td><img src="/static/cashflow/img/aeternity.png" /> Aeternity (AE)</td>
                                <td class="marketcap"></td>
                                <td class="address-link">
                                    <div class="usd">$0</div>
                                    <div class="eth"><a class="address" href="">Ξ0<i class="fa fa-external-link"></i></div>
                                </td>
                                <td>No transfers yet</td>
                                <td>0</td>
                            </tr>
                           <tr>
                                <td><img src="/static/cashflow/img/aragon.png" /> Aragon (ANT)</td>
                                <td class="marketcap">$64,692,299</td>
                                <td class="address-link">
                                    <div class="usd">$59,660,502</div>
                                    <div class="eth"><a class="address" href="">Ξ268,741<i class="fa fa-external-link"></i></a></div>
                                </td>
                                <td>No transfers yet</td>
                                <td>0</td>
                            </tr>
                            <tr>
                                <td><img src="/static/cashflow/img/augur.png" /> Augur (REP)</td>
                                <td class="marketcap">$191,477,000</td>
                                <td class="address-link">
                                    <div class="usd">$136,030</div>
                                    <div class="eth"><a class="address" href="">Ξ613 <i class="fa fa-external-link"></i> </a></div>
                                </td>
                                <td>No transfers yet</td>
                                <td>0</td>
                            </tr>
                            <tr>
                                <td><img src="/static/cashflow/img/bancor.png" /> Bancor (BNT)</td>
                                <td class="marketcap">$81,886,195</td>
                                <td class="address-link">
                                    <div class="usd">$0</div>
                                    <div class="eth"><a class="address" href="">Ξ0 <i class="fa fa-external-link"></i></a></div>
                                </td>
                                <td>No transfers yet</td>
                                <td>0</td>
                            </tr>
                            <tr>
                                <td><img src="/static/cashflow/img/basic-attention-token.png" /> Basic Attention Token (BAT)</td>
                                <td class="marketcap">$140,697,000</td>
                                <td class="address-link">
                                    <table>
                                        <tr>
                                            <td class="inset">$0</td>
                                            <td class="inset"><a class="address" href="">Ξ0 <i class="fa fa-external-link"></i></td>
                                        </tr>
                                    </table>
                                </td>
                                <td>No transfers yet</td>
                                <td>0</td>
                            </tr>
                            <tr>
                                <td>Blockchain Capital (BNT)</td>
                                <td class="marketcap"></td>
                                <td class="address-link">
                                    <table>
                                        <tr>
                                            <td class="inset">$0</td>
                                            <td class="inset"><a class="address" href="">Ξ0 <i class="fa fa-external-link"></i></td>
                                        </tr>
                                    </table>
                                </td>
                                <td>No transfers yet</td>
                                <td>0</td>
                            </tr>
                            <tr>
                                <td><img src="/static/cashflow/img/chronobank.png" /> Chronobank (TIME)</td>
                                <td class="marketcap">$12,789,132</td>
                                <td class="address-link">
                                    <table>
                                        <tr>
                                            <td class="inset">$0</td>
                                            <td class="inset"><a class="address" href="">Ξ0 <i class="fa fa-external-link"></i></td>
                                        </tr>
                                    </table>
                                </td>
                                <td>No transfers yet</td>
                                <td>0</td>
                            </tr>
                            <tr>
                                <td><img src="/static/cashflow/img/cofound-it.png" /> Cofound.it (CFI)</td>
                                <td class="marketcap">$12,860,750</td>
                                <td class="address-link">
                                    <table>
                                        <tr>
                                            <td class="inset">$0</td>
                                            <td class="inset"><a class="address" href="">Ξ0 <i class="fa fa-external-link"></i></td>
                                        </tr>
                                    </table>
                                </td>
                                <td>No transfers yet</td>
                                <td>0</td>
                            </tr>
                            <tr>
                                <td>Contingency</td>
                                <td class="marketcap"></td>
                                <td class="address-link">
                                    <table>
                                        <tr>
                                            <td class="inset">$4,157,612</td>
                                            <td class="inset"><a class="address" href="">Ξ18,728 <i class="fa fa-external-link"></i></a></td>
                                        </tr>
                                    </table>
                                </td>
                                <td>No transfers yet</td>
                                <td>0</td>
                            </tr>
                            <tr>
                                <td>Cosmos</td>
                                <td class="marketcap"></td>
                                <td class="address-link">
                                    <table>
                                        <tr>
                                            <td class="inset">$4,157,612</td>
                                            <td class="inset"><a class="address" href="">Ξ18,728 <i class="fa fa-external-link"></i></a></td>
                                        </tr>
                                    </table>
                                </td>
                                <td>No transfers yet</td>
                                <td>0</td>
                            </tr>
                            <tr>
                                <td><img src="/static/cashflow/img/digixdao.png" /> DigixDAO (DGX)</td>
                                <td class="marketcap">$140,659,600</td>
                                <td class="address-link">
                                    <span style="margin-right: 20px">$10,402,504</span><br /><a class="address" href="">Ξ46,648 <i class="fa fa-external-link"></i></a></td>
                                <td>No transfers yet</td>
                                <td>0</td>
                            </tr>
                            <tr>
                                <td><img src="/static/cashflow/img/edgeless.png" /> Edgeless (EDG)</td>
                                <td class="marketcap">$38,110,008</td>
                                <td class="address-link">
                                    <table>
                                        <tr>
                                            <td class="inset">$0</td>
                                            <td class="inset"><a class="address" href="">Ξ0 <i class="fa fa-external-link"></i></td>
                                        </tr>
                                    </table>
                                </td>
                                <td>No transfers yet</td>
                                <td>0</td>
                            </tr>
                            <tr>
                                <td><img src="/static/cashflow/img/eos.png" /> EOS (EOS)</td>
                                <td class="marketcap">$468,910,471</td>
                                <td class="address-link"><span style="margin-right: 20px">$78,474,558</span><br /><a class="address" href="">Ξ351,904 <i class="fa fa-external-link"></i></a></td>
                                <td>2017-07-28</td>
                                <td>3900</td>
                            </tr>
                            <tr>
                                <td><img src="/static/cashflow/img/etheroll.png" /> Etheroll (DICE)</td>
                                <td class="marketcap">$31,708,459</td>
                                <td class="address-link"><span style="margin-right: 20px">$3,957,135</span><br /><a class="address" href="">Ξ17,745 <i class="fa fa-external-link"></i></a></td>
                                <td>No transfers yet</td>
                                <td>0</td>
                            </tr>
                            <tr>
                                <td><img src="/static/cashflow/img/firstblood.png" /> FirstBlood (1ST)</td>
                                <td class="marketcap">$892</td>
                                <td class="address-link"><span style="margin-right: 20px">$8.92</span><br /><a class="address" href="">Ξ0.04 <i class="fa fa-external-link"></i></a></td>
                                <td>No transfers yet</td>
                                <td>0</td>
                            </tr>
                            <tr>
                                <td><img src="/static/cashflow/img/gnosis-gno.png" /> Gnosis (GNO)</td>
                                <td class="marketcap">$219,657,663</td>
                                <td class="address-link">
                                    <table>
                                        <tr>
                                            <td class="inset">$0</td>
                                            <td class="inset"><a class="address" href="">Ξ0 <i class="fa fa-external-link"></i></td>
                                        </tr>
                                    </table>
                                </td>
                                <td>No transfers yet</td>
                                <td>0</td>
                            </tr>
                            <tr>
                                <td><img src="/static/cashflow/img/golem-network-tokens.png" /> Golem (GNT)</td>
                                <td class="marketcap">$248,632,562</td>
                                <td class="address-link">
                                    <table>
                                        <tr>
                                            <td class="inset">$0</td>
                                            <td class="inset"><a class="address" href="">Ξ0 <i class="fa fa-external-link"></i></td>
                                        </tr>
                                    </table>
                                </td>
                                <td>No transfers yet</td>
                                <td>0</td>
                            </tr>
                            <tr>
                                <td><img src="/static/cashflow/img/humaniq.png" /> Humaniq (HMQ)</td>
                                <td class="marketcap">$25,268,470</td>
                                <td class="address-link">
                                    <table>
                                        <tr>
                                            <td class="inset">$0</td>
                                            <td class="inset"><a class="address" href="">Ξ0 <i class="fa fa-external-link"></i></td>
                                        </tr>
                                    </table>
                                </td>
                                <td>No transfers yet</td>
                                <td>0</td>
                            </tr>
                            <tr>
                                <td><img src="/static/cashflow/img/ICONOMI.png" /> Iconomi (ICN)</td>
                                <td class="marketcap">$270,331,346</td>
                                <td class="address-link"><span style="margin-right: 20px">$36,710,142</span><br /><a class="address" href="">Ξ164,619 <i class="fa fa-external-link"></i></a></td>
                                <td>No transfers yet</td>
                                <td>0</td>
                            </tr>
                            <tr>
                                <td><img src="/static/cashflow/img/rlc.png" /> iEx.ec (RLC)</td>
                                <td class="marketcap">$32,773,974</td>
                                <td class="address-link">
                                    <table>
                                        <tr>
                                            <td class="inset">$0</td>
                                            <td class="inset"><a class="address" href="">Ξ0 <i class="fa fa-external-link"></i></td>
                                        </tr>
                                    </table>
                                </td>
                                <td>No transfers yet</td>
                                <td>0</td>
                            </tr>
                            <tr>
                                <td><img src="/static/cashflow/img/lunyr.png" /> Lunyr (LUN)</td>
                                <td class="marketcap">$7,666,143</td>
                                <td class="address-link">
                                    <table>
                                        <tr>
                                            <td class="inset">$0</td>
                                            <td class="inset"><a class="address" href="">Ξ0 <i class="fa fa-external-link"></i></td>
                                        </tr>
                                    </table>
                                </td>
                                <td>No transfers yet</td>
                                <td>0</td>
                            </tr>
                            <tr>
                                <td><img src="/static/cashflow/img/guppy.png" /> Matchpool (GUP)</td>
                                <td class="marketcap">$9,389,325</td>
                                <td class="address-link">
                                    <table>
                                        <tr>
                                            <td class="inset">$0</td>
                                            <td class="inset"><a class="address" href="">Ξ0 <i class="fa fa-external-link"></i></td>
                                        </tr>
                                    </table>
                                </td>
                                <td>No transfers yet</td>
                                <td>0</td>
                            </tr>
                            <tr>
                                <td><img src="/static/cashflow/img/melon.png" /> Melonport (MLN)</td>
                                <td class="marketcap">$31,591,077</td>
                                <td class="address-link">
                                    <table>
                                        <tr>
                                            <td class="inset">$0</td>
                                            <td class="inset"><a class="address" href="">Ξ0 <i class="fa fa-external-link"></i></td>
                                        </tr>
                                    </table>
                                </td>
                                <td>No transfers yet</td>
                                <td>0</td>
                            </tr>
                            <tr>
                                <td><img src="/static/cashflow/img/mysterium.png" /> Mysterium (MYST)</td>
                                <td class="marketcap">$24,921,609</td>
                                <td class="address-link">
                                    <table>
                                        <tr>
                                            <td class="inset">$0</td>
                                            <td class="inset"><a class="address" href="">Ξ0 <i class="fa fa-external-link"></i></td>
                                        </tr>
                                    </table>
                                </td>
                                <td>No transfers yet</td>
                                <td>0</td>
                            </tr>
                            <tr>
                                <td><img src="/static/cashflow/img/patientory.png" /> Patientory (PTOY)</td>
                                <td class="marketcap">$15,816,290</td>
                                <td class="address-link">
                                    <table>
                                        <tr>
                                            <td class="inset">$0</td>
                                            <td class="inset"><a class="address" href="">Ξ0 <i class="fa fa-external-link"></i></td>
                                        </tr>
                                    </table>
                                </td>
                                <td>No transfers yet</td>
                                <td>0</td>
                            </tr>
                            <tr>
                                <td><img src="/static/cashflow/img/Pluton.png" /> Pluton (PLU)</td>
                                <td class="marketcap">$11,019,139</td>
                                <td class="address-link">
                                    <table>
                                        <tr>
                                            <td class="inset">$0</td>
                                            <td class="inset"><a class="address" href="">Ξ0 <i class="fa fa-external-link"></i></td>
                                        </tr>
                                    </table>
                                </td>
                                <td>No transfers yet</td>
                                <td>0</td>
                            </tr>
                            <tr>
                                <td><img src="/static/cashflow/img/populous.png" /> Populous (PPT)</td>
                                <td class="marketcap">$147,929,888</td>
                                <td class="address-link">
                                    <table>
                                        <tr>
                                            <td class="inset">$0</td>
                                            <td class="inset"><a class="address" href="">Ξ0 <i class="fa fa-external-link"></i></td>
                                        </tr>
                                    </table>
                                </td>
                                <td>No transfers yet</td>
                                <td>0</td>
                            </tr>
                            <tr>
                                <td><img src="/static/cashflow/img/qtum.png" /> Qtum (QTUM)</td>
                                <td class="marketcap">$474,672,700</td>
                                <<td class="address-link">
                                <table>
                                    <tr>
                                        <td class="inset">$0</td>
                                        <td class="inset"><a class="address" href="">Ξ0 <i class="fa fa-external-link"></i></td>
                                    </tr>
                                </table>
                            </td>
                                <td>No transfers yet</td>
                                <td>0</td>
                            </tr>
                            <tr>
                                <td><img src="/static/cashflow/img/san_28.png" /> Santiment (SAN)</td>
                                <td class="marketcap">$12,640,715</td>
                                <td class="address-link"><span style="margin-right: 20px">$9,035,223</span><br /><a class="address" href="">Ξ40,516 <i class="fa fa-external-link"></i></a></td>
                                <td>2017-07-13</td>
                                <td>0</td>
                            </tr>
                            <tr>
                                <td><img src="/static/cashflow/img/sngls.png" /> SingularDTV (SNGLS)</td>
                                <td class="marketcap">$83,296,800</td>
                                <td class="address-link">
                                    <table>
                                        <tr>
                                            <td class="inset">$0</td>
                                            <td class="inset"><a class="address" href="">Ξ0 <i class="fa fa-external-link"></i></td>
                                        </tr>
                                    </table>
                                </td>
                                <td>No transfers yet</td>
                                <td>0</td>
                            </tr>
                            <tr>
                                <td><img src="/static/cashflow/img/status.png" /> Status (SNT)</td>
                                <td class="marketcap">$195,889,722</td>
                                <td class="address-link"><span style="margin-right: 20px">$66,578,244</span><br /><a class="address" href="">Ξ298,557 <i class="fa fa-external-link"></i></a></td>
                                <td>No transfers yet</td>
                                <td>0</td>
                            </tr>
                            <tr>
                                <td><img src="/static/cashflow/img/storj.png" /> StorJ (STORJ)</td>
                                <td class="marketcap">$29,734,042</td>
                                <td class="address-link">
                                    <table>
                                        <tr>
                                            <td class="inset">$0</td>
                                            <td class="inset"><a class="address" href="">Ξ0 <i class="fa fa-external-link"></i></td>
                                        </tr>
                                    </table>
                                </td>
                                <td>No transfers yet</td>
                                <td>0</td>
                            </tr>
                            <tr>
                                <td><img src="/static/cashflow/img/SwarmCity.png" /> Swarm City (SWT)</td>
                                <td class="marketcap">$9,040,966</td>
                                <td class="address-link">
                                    <table>
                                        <tr>
                                            <td class="inset">$0</td>
                                            <td class="inset"><a class="address" href="">Ξ0 <i class="fa fa-external-link"></i></td>
                                        </tr>
                                    </table>
                                </td>
                                <td>No transfers yet</td>
                                <td>0</td>
                            </tr>
                            <tr>
                                <td><img src="/static/cashflow/img/taas.png" /> TaaS (TAAS)</td>
                                <td class="marketcap">$23,107,272</td>
                                <td class="address-link"><span style="margin-right: 20px">$3,038,152</span><br /><a class="address" href="">Ξ13,624 <i class="fa fa-external-link"></i></a></td>
                                <td>No transfers yet</td>
                                <td>0</td>
                            </tr>
                            <tr>
                                <td><img src="/static/cashflow/img/tenx.png" /> TenX (PAY)</td>
                                <td class="marketcap">$149,850,924</td>
                                <td class="address-link">
                                    <table>
                                        <tr>
                                            <td class="inset">$0</td>
                                            <td class="inset"><a class="address" href="">Ξ0 <i class="fa fa-external-link"></i></td>
                                        </tr>
                                    </table>
                                </td>
                                <td>No transfers yet</td>
                                <td>0</td>
                            </tr>
                            <tr>
                                <td>Tezos (TEZ)</td>
                                <td class="marketcap"></td>
                                <td class="address-link">
                                    <table>
                                        <tr>
                                            <td class="inset">$0</td>
                                            <td class="inset"><a class="address" href="">Ξ0 <i class="fa fa-external-link"></i></td>
                                        </tr>
                                    </table>
                                </td>
                                <td>No transfers yet</td>
                                <td>0</td>
                            </tr>
                            <tr>
                                <td><img src="/static/cashflow/img/tokencard.png" /> Tokencard (TKN)</td>
                                <td class="marketcap">$17,130,922 </td>
                                <td class="address-link"><span style="margin-right: 20px">$9,842</span><br /><a class="address" href="">Ξ44.13 <i class="fa fa-external-link"></i></a></td>
                                <td>No transfers yet</td>
                                <td>0</td>
                            </tr>
                            <tr>
                                <td><img src="/static/cashflow/img/trust.png" /> WeTrust (TRST)</td>
                                <td class="marketcap">$15,318,877</td>
                                <td class="address-link">
                                    <table>
                                        <tr>
                                            <td class="inset">$0</td>
                                            <td class="inset"><a class="address" href="">Ξ0 <i class="fa fa-external-link"></i></td>
                                        </tr>
                                    </table>
                                </td>
                                <td>No transfers yet</td>
                                <td>0</td>
                            </tr>
                            <tr>
                                <td><img src="/static/cashflow/img/wings.png" /> Wings (WINGS)</td>
                                <td class="marketcap">$39,061,071</td>
                                <td class="address-link">
                                    <table>
                                        <tr>
                                            <td class="inset">$0</td>
                                            <td class="inset"><a class="address" href="">Ξ0 <i class="fa fa-external-link"></i></td>
                                        </tr>
                                    </table>
                                </td>
                                <td>No transfers yet</td>
                                <td>0</td>
                            </tr>
                            </tbody>
                        </table> -->

                        <table id="projects" class="table table-condensed table-hover" cellspacing="0" width="100%">
                            <thead>
                            <tr>
                                <th>Project</th>
                                <th title="also called an underscore">Market Cap</th>
                                <th>Balance (USD/ETH)</th>
                                <th>Last Outgoing TX</th>
                                <th>ETH Sent</th>
                            </tr>
                            </thead>
                            <tbody class='whaletable'>
                            <tr>
                                <td><img src="/static/cashflow/img/aeternity.png" /> Aeternity (AE)</td>
                                <td class="marketcap"></td>
                                <td class="address-link">
                                    <div class="wallet">
                                        <div class="usd first">$0</div>
                                        <div class="eth"><!-- <i class="fa fa-question-circle-o"></i> --><a class="address" href="">Ξ0<i class="fa fa-external-link"></i></a></div>
                                    </div>
                                </td>
                                <td>No transfers yet</td>
                                <td>0</td>
                            </tr>
                            <tr>
                                <td><img src="/static/cashflow/img/aragon.png" /> Aragon (ANT)</td>
                                <td class="marketcap">$64,692,299</td>
                                <td class="address-link">
                                    <div class="wallet">
                                        <div class="usd first">$59,660,502</div>
                                        <div class="eth"><a class="address" href="">Ξ268,741<i class="fa fa-external-link"></i></a></div>
                                    </div>
                                </td>
                                <td>No transfers yet</td>
                                <td>0</td>
                            </tr>
                            <tr>
                                <td><img src="/static/cashflow/img/augur.png" /> Augur (REP)</td>
                                <td class="marketcap">$191,477,000</td>
                                <td class="address-link">
                                    <div class="wallet">
                                        <div class="usd first">$136,030</div>
                                        <div class="eth"><a class="address" href="">Ξ613<i class="fa fa-external-link"></i></a></div>
                                    </div>
                                </td>
                                <td>No transfers yet</td>
                                <td>0</td>
                            </tr>
                            <tr>
                                <td><img src="/static/cashflow/img/bancor.png" /> Bancor (BNT)</td>
                                <td class="marketcap">$107,990,000</td>
                                <td class="address-link">
                                    <div class="wallet">
                                        <div class="usd first">$3,909,240</div>
                                        <div class="eth multi"><a class="address" href="">Ξ12000<i class="fa fa-external-link"></i></a></div>
                                    </div>
                                    <div class="wallet">
                                        <div class="usd">$300</div>
                                        <div class="eth multi"><a class="address" href="">Ξ100<i class="fa fa-external-link"></i></a></div>
                                    </div>
                                    <div class="wallet">
                                        <div class="usd">$5,000</div>
                                        <div class="eth"><a class="address" href="">Ξ2000<i class="fa fa-external-link"></i></a></div>
                                    </div>
                                </td>
                                <td>No transfers yet</td>
                                <td>0</td>
                            </tr>
                            <tr>
                                <td><img src="/static/cashflow/img/basic-attention-token.png" /> Basic Attention Token (BAT)</td>
                                <td class="marketcap">$140,697,000</td>
                                <td class="address-link">
                                    <div class="wallet">
                                        <div class="usd first">$0</div>
                                        <div class="eth"><!-- <i class="fa fa-question-circle-o"></i> --><a class="address" href="">Ξ0<i class="fa fa-external-link"></i></a></div>
                                    </div>
                                </td>
                                <td>No transfers yet</td>
                                <td>0</td>
                            </tr>
                            <tr>
                                <td>Blockchain Capital (BNT)</td>
                                <td class="marketcap"></td>
                                <td class="address-link">
                                    <div class="wallet">
                                        <div class="usd first">$0</div>
                                        <div class="eth"><!-- <i class="fa fa-question-circle-o"></i> -->Ξ0<i class="fa fa-external-link"></i></a></div>
                                    </div>
                                </td>
                                <td>No transfers yet</td>
                                <td>0</td>
                            </tr>
                            <tr>
                                <td><img src="/static/cashflow/img/chronobank.png" /> Chronobank (TIME)</td>
                                <td class="marketcap">$12,789,132</td>
                                <td class="address-link">
                                    <div class="wallet">
                                        <div class="usd first">$0</div>
                                        <div class="eth"><!-- <i class="fa fa-question-circle-o"></i> --><a class="address" href="">Ξ0<i class="fa fa-external-link"></i></a></div>
                                    </div>
                                </td>
                                <td>No transfers yet</td>
                                <td>0</td>
                            </tr>
                            <tr>
                                <td><img src="/static/cashflow/img/cofound-it.png" /> Cofound.it (CFI)</td>
                                <td class="marketcap">$12,860,750</td>
                                <td class="address-link">
                                    <div class="wallet">
                                        <div class="usd first">$0</div>
                                        <div class="eth"><a class="address" href="">Ξ0<i class="fa fa-external-link"></i></a></div>
                                    </div>
                                </td>
                                <td>No transfers yet</td>
                                <td>0</td>
                            </tr>
                            <tr>
                                <td>Contingency</td>
                                <td class="marketcap"></td>
                                <td class="address-link">
                                    <div class="wallet">
                                        <div class="usd first">$4,157,612</div>
                                        <div class="eth"><a class="address" href="">Ξ18,728<i class="fa fa-external-link"></i></a></div>
                                    </div>
                                </td>
                                <td>No transfers yet</td>
                                <td>0</td>
                            </tr>
                            <tr>
                                <td>Cosmos</td>
                                <td class="marketcap"></td>
                                <td class="address-link">
                                    <div class="wallet">
                                        <div class="usd first">$4,157,612</div>
                                        <div class="eth"><a class="address" href="">Ξ18,728<i class="fa fa-external-link"></i></a></div>
                                    </div>
                                </td>
                                <td>No transfers yet</td>
                                <td>0</td>
                            </tr>
                            <tr>
                                <td><img src="/static/cashflow/img/digixdao.png" /> DigixDAO (DGX)</td>
                                <td class="marketcap">$140,659,600</td>
                                <td class="address-link">
                                    <div class="wallet">
                                        <div class="usd first">$10,402,504</div>
                                        <div class="eth"><a class="address" href="">Ξ46,648<i class="fa fa-external-link"></i></a></div>
                                    </div>
                                </td>
                                <td>No transfers yet</td>
                                <td>0</td>
                            </tr>
                            <tr>
                                <td><img src="/static/cashflow/img/edgeless.png" /> Edgeless (EDG)</td>
                                <td class="marketcap">$38,110,008</td>
                                <td class="address-link">
                                    <div class="wallet">
                                        <div class="usd first">$0</div>
                                        <div class="eth"><a class="address" href="">Ξ0<i class="fa fa-external-link"></i></a></div>
                                    </div>
                                </td>
                                <td>No transfers yet</td>
                                <td>0</td>
                            </tr>
                            <tr>
                                <td><img src="/static/cashflow/img/eos.png" /> EOS (EOS)</td>
                                <td class="marketcap">$468,910,471</td>
                                <td class="address-link">
                                    <div class="wallet">
                                        <div class="usd first">$78,474,558</div>
                                        <div class="eth"><a class="address" href="">Ξ351,904<i class="fa fa-external-link"></i></a></div>
                                    </div>
                                </td>
                                <td>2017-07-28</td>
                                <td>3900</td>
                            </tr>
                            <tr>
                                <td><img src="/static/cashflow/img/etheroll.png" /> Etheroll (DICE)</td>
                                <td class="marketcap">$31,708,459</td>
                                <td class="address-link">
                                    <div class="wallet">
                                        <div class="usd first">$3,957,135</div>
                                        <div class="eth"><a class="address" href="">Ξ17,745<i class="fa fa-external-link"></i></a></div>
                                    </div>
                                </td>
                                <td>No transfers yet</td>
                                <td>0</td>
                            </tr>
                            <tr>
                                <td><img src="/static/cashflow/img/firstblood.png" /> FirstBlood (1ST)</td>
                                <td class="marketcap">$892</td>
                                <td class="address-link">
                                    <div class="wallet">
                                        <div class="usd first">$8.92</div>
                                        <div class="eth"><a class="address" href="">Ξ0.04<i class="fa fa-external-link"></i></a></div>
                                    </div>
                                </td>
                                <td>No transfers yet</td>
                                <td>0</td>
                            </tr>
                            <tr>
                                <td><img src="/static/cashflow/img/gnosis-gno.png" /> Gnosis (GNO)</td>
                                <td class="marketcap">$219,657,663</td>
                                <td class="address-link">
                                    <div class="wallet">
                                        <div class="usd first">$0</div>
                                        <div class="eth"><a class="address" href="">Ξ0<i class="fa fa-external-link"></i></a></div>
                                    </div>
                                </td>
                                <td>No transfers yet</td>
                                <td>0</td>
                            </tr>
                            <tr>
                                <td><img src="/static/cashflow/img/golem-network-tokens.png" /> Golem (GNT)</td>
                                <td class="marketcap">$248,632,562</td>
                                <td class="address-link">
                                    <div class="wallet">
                                        <div class="usd first">$0</div>
                                        <div class="eth"><a class="address" href="">Ξ0<i class="fa fa-external-link"></i></a></div>
                                    </div>
                                </td>
                                <td>No transfers yet</td>
                                <td>0</td>
                            </tr>
                            <tr>
                                <td><img src="/static/cashflow/img/humaniq.png" /> Humaniq (HMQ)</td>
                                <td class="marketcap">$25,268,470</td>
                                <td class="address-link">
                                    <div class="wallet">
                                        <div class="usd first">$0</div>
                                        <div class="eth"><a class="address" href="">Ξ0<i class="fa fa-external-link"></i></a></div>
                                    </div>
                                </td>
                                <td>No transfers yet</td>
                                <td>0</td>
                            </tr>
                            <tr>
                                <td><img src="/static/cashflow/img/ICONOMI.png" /> Iconomi (ICN)</td>
                                <td class="marketcap">$270,331,346</td>
                                <td class="address-link">
                                    <div class="wallet">
                                        <div class="usd first">$36,710,142</div>
                                        <div class="eth"><a class="address" href="">Ξ164,619<i class="fa fa-external-link"></i></a></div>
                                    </div>
                                </td>
                                <td>No transfers yet</td>
                                <td>0</td>
                            </tr>
                            <tr>
                                <td><img src="/static/cashflow/img/rlc.png" /> iEx.ec (RLC)</td>
                                <td class="marketcap">$32,773,974</td>
                                <td class="address-link">
                                    <div class="wallet">
                                        <div class="usd first">$0</div>
                                        <div class="eth"><a class="address" href="">Ξ0<i class="fa fa-external-link"></i></a></div>
                                    </div>
                                </td>
                                <td>No transfers yet</td>
                                <td>0</td>
                            </tr>
                            <tr>
                                <td><img src="/static/cashflow/img/lunyr.png" /> Lunyr (LUN)</td>
                                <td class="marketcap">$7,666,143</td>
                                <td class="address-link">
                                    <div class="wallet">
                                        <div class="usd first">$0</div>
                                        <div class="eth"><a class="address" href="">Ξ0<i class="fa fa-external-link"></i></a></div>
                                    </div>
                                </td>
                                <td>No transfers yet</td>
                                <td>0</td>
                            </tr>
                            <tr>
                                <td><img src="/static/cashflow/img/guppy.png" /> Matchpool (GUP)</td>
                                <td class="marketcap">$9,389,325</td>
                                <td class="address-link">
                                    <div class="wallet">
                                        <div class="usd first">$0</div>
                                        <div class="eth"><a class="address" href="">Ξ0<i class="fa fa-external-link"></i></a></div>
                                    </div>
                                </td>
                                <td>No transfers yet</td>
                                <td>0</td>
                            </tr>
                            <tr>
                                <td><img src="/static/cashflow/img/melon.png" /> Melonport (MLN)</td>
                                <td class="marketcap">$31,591,077</td>
                                <td class="address-link">
                                    <div class="wallet">
                                        <div class="usd first">$0</div>
                                        <div class="eth"><a class="address" href="">Ξ0<i class="fa fa-external-link"></i></a></div>
                                    </div>
                                </td>
                                <td>No transfers yet</td>
                                <td>0</td>
                            </tr>
                            <tr>
                                <td><img src="/static/cashflow/img/mysterium.png" /> Mysterium (MYST)</td>
                                <td class="marketcap">$24,921,609</td>
                                <td class="address-link">
                                    <div class="wallet">
                                        <div class="usd first">$0</div>
                                        <div class="eth"><a class="address" href="">Ξ0<i class="fa fa-external-link"></i></a></div>
                                    </div>
                                </td>
                                <td>No transfers yet</td>
                                <td>0</td>
                            </tr>
                            <tr>
                                <td><img src="/static/cashflow/img/patientory.png" /> Patientory (PTOY)</td>
                                <td class="marketcap">$15,816,290</td>
                                <td class="address-link">
                                    <div class="wallet">
                                        <div class="usd first">$0</div>
                                        <div class="eth"><a class="address" href="">Ξ0<i class="fa fa-external-link"></i></a></div>
                                    </div>
                                </td>
                                <td>No transfers yet</td>
                                <td>0</td>
                            </tr>
                            <tr>
                                <td><img src="/static/cashflow/img/Pluton.png" /> Pluton (PLU)</td>
                                <td class="marketcap">$11,019,139</td>
                                <td class="address-link">
                                    <div class="wallet">
                                        <div class="usd first">$0</div>
                                        <div class="eth"><a class="address" href="">Ξ0<i class="fa fa-external-link"></i></a></div>
                                    </div>
                                </td>
                                <td>No transfers yet</td>
                                <td>0</td>
                            </tr>
                            <tr>
                                <td><img src="/static/cashflow/img/populous.png" /> Populous (PPT)</td>
                                <td class="marketcap">$147,929,888</td>
                                <td class="address-link">
                                    <div class="wallet">
                                        <div class="usd first">$0</div>
                                        <div class="eth"><a class="address" href="">Ξ0<i class="fa fa-external-link"></i></a></div>
                                    </div>
                                </td>
                                <td>No transfers yet</td>
                                <td>0</td>
                            </tr>
                            <tr>
                                <td><img src="/static/cashflow/img/qtum.png" /> Qtum (QTUM)</td>
                                <td class="marketcap">$474,672,700</td>
                                <td class="address-link">
                                    <div class="wallet">
                                        <div class="usd first">$0</div>
                                        <div class="eth"><a class="address" href="">Ξ0<i class="fa fa-external-link"></i></a></div>
                                    </div>
                                </td>
                                <td>No transfers yet</td>
                                <td>0</td>
                            </tr>
                            <tr>
                                <td><img src="/static/cashflow/img/san_28.png" /> Santiment (SAN)</td>
                                <td class="marketcap">$12,640,715</td>
                                <td class="address-link">
                                    <div class="wallet">
                                        <div class="usd first">$9,035,223</div>
                                        <div class="eth"><a class="address" href="">Ξ40,516<i class="fa fa-external-link"></i></a></div>
                                    </div>
                                </td>
                                <td>2017-07-13</td>
                                <td>0</td>
                            </tr>
                            <tr>
                                <td><img src="/static/cashflow/img/sngls.png" /> SingularDTV (SNGLS)</td>
                                <td class="marketcap">$83,296,800</td>
                                <td class="address-link">
                                    <div class="wallet">
                                        <div class="usd first">$0</div>
                                        <div class="eth"><a class="address" href="">Ξ0<i class="fa fa-external-link"></i></a></div>
                                    </div>
                                </td>
                                <td>No transfers yet</td>
                                <td>0</td>
                            </tr>
                            <tr>
                                <td><img src="/static/cashflow/img/status.png" /> Status (SNT)</td>
                                <td class="marketcap">$195,889,722</td>
                                <td class="address-link">
                                    <div class="wallet">
                                        <div class="usd first">$66,578,244</div>
                                        <div class="eth"><a class="address" href="">Ξ298,557<i class="fa fa-external-link"></i></a></div>
                                    </div>
                                </td>
                                <td>No transfers yet</td>
                                <td>0</td>
                            </tr>
                            <tr>
                                <td><img src="/static/cashflow/img/storj.png" /> StorJ (STORJ)</td>
                                <td class="marketcap">$29,734,042</td>
                                <td class="address-link">
                                    <div class="wallet">
                                        <div class="usd first">$0</div>
                                        <div class="eth"><a class="address" href="">Ξ0<i class="fa fa-external-link"></i></a></div>
                                    </div>
                                </td>
                                <td>No transfers yet</td>
                                <td>0</td>
                            </tr>
                            <tr>
                                <td><img src="/static/cashflow/img/SwarmCity.png" /> Swarm City (SWT)</td>
                                <td class="marketcap">$9,040,966</td>
                                <td class="address-link">
                                    <div class="wallet">
                                        <div class="usd first">$0</div>
                                        <div class="eth"><a class="address" href="">Ξ0<i class="fa fa-external-link"></i></a></div>
                                    </div>
                                </td>
                                <td>No transfers yet</td>
                                <td>0</td>
                            </tr>
                            <tr>
                                <td><img src="/static/cashflow/img/taas.png" /> TaaS (TAAS)</td>
                                <td class="marketcap">$23,107,272</td>
                                <td class="address-link">
                                    <div class="wallet">
                                        <div class="usd first">$3,038,152</div>
                                        <div class="eth"><a class="address" href="">Ξ13,624<i class="fa fa-external-link"></i></a></div>
                                    </div>
                                </td>
                                <td>No transfers yet</td>
                                <td>0</td>
                            </tr>
                            <tr>
                                <td><img src="/static/cashflow/img/tenx.png" /> TenX (PAY)</td>
                                <td class="marketcap">$149,850,924</td>
                                <td class="address-link">
                                    <div class="wallet">
                                        <div class="usd first">$0</div>
                                        <div class="eth"><a class="address" href="">Ξ0<i class="fa fa-external-link"></i></a></div>
                                    </div>
                                </td>
                                <td>No transfers yet</td>
                                <td>0</td>
                            </tr>
                            <tr>
                                <td>Tezos (TEZ)</td>
                                <td class="marketcap"></td>
                                <td class="address-link">
                                    <div class="wallet">
                                        <div class="usd first">$0</div>
                                        <div class="eth"><a class="address" href="">Ξ0<i class="fa fa-external-link"></i></a></div>
                                    </div>
                                </td>
                                <td>No transfers yet</td>
                                <td>0</td>
                            </tr>
                            <tr>
                                <td><img src="/static/cashflow/img/tokencard.png" /> Tokencard (TKN)</td>
                                <td class="marketcap">$17,130,922 </td>
                                <td class="address-link">
                                    <div class="wallet">
                                        <div class="usd first">$9,842</div>
                                        <div class="eth"><a class="address" href="">Ξ44.13<i class="fa fa-external-link"></i></a></div>
                                    </div>
                                </td>
                                <td>No transfers yet</td>
                                <td>0</td>
                            </tr>
                            <tr>
                                <td><img src="/static/cashflow/img/trust.png" /> WeTrust (TRST)</td>
                                <td class="marketcap">$15,318,877</td>
                                <td class="address-link">
                                    <div class="wallet">
                                        <div class="usd first">$0</div>
                                        <div class="eth"><a class="address" href="">Ξ0<i class="fa fa-external-link"></i></a></div>
                                    </div>
                                </td>
                                <td>No transfers yet</td>
                                <td>0</td>
                            </tr>
                            <tr>
                                <td><img src="/static/cashflow/img/wings.png" /> Wings (WINGS)</td>
                                <td class="marketcap">$39,061,071</td>
                                <td class="address-link">
                                    <div class="wallet">
                                        <div class="usd first">$0</div>
                                        <div class="eth"><a class="address" href="">Ξ0<i class="fa fa-external-link"></i></a></div>
                                    </div>
                                </td>
                                <td>No transfers yet</td>
                                <td>0</td>
                            </tr>
                            </tbody>
                        </table>
                    </div>
                </div>
            </div>
        </div>
    </div>
    <script>

        $(document).ready(function () {

            $('.table-hover').DataTable({

                "dom": "<'row'<'col-sm-7'i><'col-sm-5'f>>" +
                "<'row'<'col-sm-12'tr>>" +
                "<'row'<'col-sm-5'><'col-sm-7'>>",
                "paging": false,
                fixedHeader: true,
                language: {
                    search: "_INPUT_",
                    searchPlaceholder: "Search"
                },
                responsive: {
                    details: {
                        display: $.fn.dataTable.Responsive.display.childRowImmediate,
                        type: ''
                    }
                }

            });

        });
    </script>
   `}} />
  </div>
)

export default Index
