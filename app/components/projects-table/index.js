const ProjectsTable = (props) => (
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
            {
              props.data.projects.map((project) => {
                var marketCapUsd;
                if(project.market_cap_usd !== null){
                  marketCapUsd = "$" + project.market_cap_usd.toLocaleString('en-US', { maximumFractionDigits: 0 });
                } else {
                  marketCapUsd = "No data";
                }

                var logoUrl = project.logo_url !== null ? project.logo_url.toString().toLowerCase() : "";
                return (
                  <tr>
                    <td><img src={ "/static/cashflow/img/" + logoUrl } />{ project.name } ({ project.ticker })</td>
                    <td className="marketcap">{ marketCapUsd }</td>
                    <td className="address-link" data-order={ project.balance }>
                    {
                      project.wallets.map((wallet) => {
                        var balance = wallet.balance !== null ? wallet.balance : 0;
                        return (
                          <div className="wallet">
                            <div className="usd first">${(balance * props.data.eth_price).toLocaleString('en-US', {maximumFractionDigits: 0})}</div>
                            <div className="eth">
                              <a className="address" href={ "https://etherscan.io/address/" + wallet.address } target="_blank">Ξ{ balance.toLocaleString('en-US') }
                                <i className="fa fa-external-link"></i>
                              </a>
                            </div>
                          </div>
                        )
                      })
                    }
                    </td>
                    <td>
                    {
                      project.wallets.map((wallet) => {
                        var lastOutgoing = wallet.last_outgoing !== null ? wallet.last_outgoing : 'No recent transfers';
                        return (
                          <div>
                            { lastOutgoing }
                          </div>
                        )
                      })
                    }
                    </td>
                    <td>
                    {
                      project.wallets.map((wallet) => {
                        var txOut = wallet.tx_out !== null ? wallet.tx_out : 0;
                        return (
                          <div>
                            { txOut.toLocaleString('en-US') }
                          </div>
                        )
                      })
                    }
                    </td>
                  </tr>
                )
              })
            }
            </tbody>
          </table>
        </div>
      </div>
    </div>
  </div>
)

export default ProjectsTable
