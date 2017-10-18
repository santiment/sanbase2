import fetch from 'isomorphic-unfetch'
import { WEBSITE_URL } from '../config'
import Layout from '../components/Layout'

const Index = (props) => (
<Layout>
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
</Layout>
)

Index.getInitialProps = async function() {
  const res = await fetch(WEBSITE_URL + '/api/cashflow')
  const data = await res.json()

  return {
    data: data
  }
}

export default Index
