import Head from 'next/head'
import fetch from 'isomorphic-unfetch'
import { WEBSITE_URL } from '../../config'

const Index = (props) => (
  <div>
  <Head>
    <meta charset="utf-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1, shrink-to-fit=no" />
    <link rel="stylesheet" href="https://maxcdn.bootstrapcdn.com/bootstrap/4.0.0-alpha.6/css/bootstrap.min.css"
          integrity="sha384-rwoIResjU2yc3z8GV/NPeZWAv56rSmLldC3R/AZzGRnGxQQKnKkoFVhFQhNUwEyJ" crossorigin="anonymous" />
    <link href="https://fonts.googleapis.com/icon?family=Material+Icons" rel="stylesheet" />
    <link href="https://fonts.googleapis.com/css?family=Roboto:300,400,700" rel="stylesheet" />
    <script src="https://use.fontawesome.com/6f993f4769.js"></script>
    <link rel="stylesheet" href="https://cdn.datatables.net/1.10.15/css/jquery.dataTables.min.css"/>
    <link rel="stylesheet" href="https://cdn.datatables.net/responsive/2.1.1/css/responsive.dataTables.min.css"/>
    <link rel="stylesheet" href="https://cdn.datatables.net/fixedheader/3.1.2/css/fixedHeader.bootstrap.min.css"/>
    <link rel="stylesheet" href="/static/cashflow/css/style_dapp_mvp1.css"/>
    <script src="https://code.jquery.com/jquery-3.0.0.min.js"></script>
    <script src="https://cdnjs.cloudflare.com/ajax/libs/tether/1.4.0/js/tether.min.js"
            integrity="sha384-DztdAPBWPRXSA/3eYEEUWrWCy7G5KFbe8fFjk5JAIxUYHKkDx6Qin1DkWx51bBrb"
            crossorigin="anonymous"></script>
    <script src="https://maxcdn.bootstrapcdn.com/bootstrap/4.0.0-alpha.6/js/bootstrap.min.js"
            integrity="sha384-vBWWzlZJ8ea9aCX4pEW3rVHjgjt7zpkNpZk+02D9phzyeVkE+jo0ieGizqPLForn"
            crossorigin="anonymous"></script>
    <script src="https://www.kryogenix.org/code/browser/sorttable/sorttable.js"></script>
    <script src="https://cdn.datatables.net/1.10.15/js/jquery.dataTables.min.js"></script>
    <script src="https://cdn.datatables.net/1.10.15/js/dataTables.bootstrap4.min.js"></script>
    <script src="https://cdn.datatables.net/responsive/2.1.1/js/dataTables.responsive.min.js"></script>
    <script src="https://cdn.datatables.net/responsive/2.1.1/js/responsive.bootstrap.min.js"></script>
    <script src="https://cdn.datatables.net/fixedheader/3.1.2/js/dataTables.fixedHeader.min.js"></script>
    <script dangerouslySetInnerHTML={{ __html: `
      (function(i,s,o,g,r,a,m){i['GoogleAnalyticsObject']=r;i[r]=i[r]||function(){
      (i[r].q=i[r].q||[]).push(arguments)},i[r].l=1*new Date();a=s.createElement(o),
      m=s.getElementsByTagName(o)[0];a.async=1;a.src=g;m.parentNode.insertBefore(a,m)
      })(window,document,'script','https://www.google-analytics.com/analytics.js','ga');

      ga('create', 'UA-100571693-1', 'auto');
      ga('send', 'pageview');
     `}} />
  </Head>
  <div className="nav-side-menu">
      <div className="brand"><img src="/static/cashflow/img/logo_sanbase.png" width="115" height="22" alt="SANbase"/></div>
      <i className="fa fa-bars fa-2x toggle-btn" data-toggle="collapse" data-target="#menu-content"></i>
      <div className="menu-list">
          <ul id="menu-content" className="menu-content collapse out">
              <li>
                  <a href="#">
                      <i className="fa fa-home fa-md"></i> Dashboard (tbd)
                  </a>
              </li>
              <li data-toggle="collapse" data-target="#products" className="active">
                  <a href="#" className="active"><i className="fa fa-list fa-md"></i> Data-feeds <span className="arrow"></span></a>
              </li>
              <ul className="sub-menu" id="products">
                  <li><a href="#">Overview (tbd)</a></li>
                  <li className="active"><a href="#" className="active">Cash Flow</a></li>
              </ul>
              <li>
                  <a href="signals"><i className="fa fa-th fa-md"></i> Signals </a>
              </li>
              <li>
                <a href="roadmap"><i className="fa fa-comment-o fa-md"></i> Roadmap </a>
              </li>
          </ul>
      </div>
  </div>
  <div className="container" id="main">
      <div className="row">
          <div className="col-lg-5">
              <h1>Cash Flow</h1>
          </div>
          <div className="col-lg-7 community-actions">
               <span className="legal">brought to you by <a href="https://santiment.net" target="_blank">Santiment</a>
               <br />
               NOTE: This app is a prototype. We give no guarantee data is correct as we are in active development.</span>
          </div>
      </div>
      <div className="row">
          <div className="col-12">
              <div className="panel">
                  <div className="sortable table-responsive">
                      <table id="projects" className="table table-condensed table-hover" cellspacing="0" width="100%">
                          <thead>
                          <tr>
                              <th>Project</th>
                              <th>Market Cap</th>
                              <th className="sorttable_numeric">Balance (USD/ETH)</th>
                              <th>Last outgoing TX</th>
                              <th>ETH sent</th>
                          </tr>
                          </thead>
                          <tbody className='whaletable'>
                          {props.data.projects.map((project) =>
                            {
                              var market_cap_usd;
                              if(project.market_cap_usd !== null)
                              {
                                market_cap_usd = "$" + project.market_cap_usd.toLocaleString('en-US', {maximumFractionDigits: 0});
                              }
                              else
                              {
                                market_cap_usd = "No data";
                              }

                              var logo_url = project.logo_url !== null ? project.logo_url.toString().toLowerCase() : "";

                              return(
                              <tr>
                                  <td><img src={"/static/cashflow/img/"+logo_url} />{project.name} ({project.ticker})</td>
                                  <td className="marketcap">{market_cap_usd}</td>
                                  <td className="address-link" data-order={project.balance}>
                                  {project.wallets.map((wallet) =>
                                    {
                                      var balance = wallet.balance !== null ? wallet.balance : 0;
                                      return (
                                      <div className="wallet">
                                        <div className="usd first">${(balance * props.data.eth_price).toLocaleString('en-US', {maximumFractionDigits: 0})}</div>
                                        <div className="eth">
                                            <a className="address" href={"https://etherscan.io/address/"+wallet.address} target="_blank">Ξ{balance.toLocaleString('en-US')}
                                                <i className="fa fa-external-link"></i>
                                            </a>
                                        </div>
                                      </div>
                                    )
                                  })}
                                  </td>
                                  <td>
                                  {project.wallets.map((wallet) =>
                                    {
                                      return (
                                        <div>
                                          {wallet.last_outgoing}
                                        </div>
                                      )
                                    })}
                                  </td>
                                  <td>
                                  {project.wallets.map((wallet) =>
                                    {
                                      var tx_out = wallet.tx_out !== null ? wallet.tx_out : 0;
                                      return(
                                      <div>
                                        {tx_out.toLocaleString('en-US')}
                                      </div>
                                    )
                                  })}
                                  </td>
                              </tr>
                          )
                        })}
                          </tbody>
                      </table>
                  </div>
              </div>
          </div>
      </div>
  </div>
  <script dangerouslySetInnerHTML={{ __html: `
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
          "order": [[ 1, "desc" ]],

            responsive: {
                details: {
                    display: $.fn.dataTable.Responsive.display.childRowImmediate,
                    type: ''
                }
            }

        });

    });
   `}} />
  </div>
)

Index.getInitialProps = async function() {
  const res = await fetch(WEBSITE_URL + '/api/cashflow')
  const data = await res.json()

  return {
    data: data
  }
}

export default Index
