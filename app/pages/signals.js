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
                    <a href="#"><i class="fa fa-list fa-md"></i> Data-feeds <!-- <span class="arrow"></span> --></a>
                </li>
                <ul class="sub-menu collapse" id="products">
                    <!-- <li><a href="#">Projects</li>
                    <li><a href="#">Token Sales</a></li> -->
                    <li><a href="#">Projects (tbd)</a></li>
                    <li><a href="index">Cash Flow </a> <!-- <span class="badge badge-info">2</span> --></li>
                </ul>
                <li>
                    <a href="signals" class="active"><i class="fa fa-th fa-md"></i> Signals </a>
                </li>
                <li>
                    <a href="roadmap"><i class="fa fa-map fa-md"></i> Roadmap</a>
                </li>
                <!-- <li data-toggle="collapse" data-target="#new" class="collapsed">
                    <a href="roadmap.html" class="active"><i class="fa fa-comment-o fa-md"></i> Roadmap (tbd) </a>
                </li> -->
            </ul>
        </div>
    </div>
    <div class="container vert-stretch" id="main">
        <div class="row topbar">
            <div class="col-lg-6">
                <div style="padding-top: 24px; padding-left: 16px;">

                    <!-- <i class="material-icons">search</i> -->
                </div>
                <!-- <div class="input-group">
                    <span class="input-group-addon"><i class="material-icons">search</i></span>
                    <input type="text" class="form-control" placeholder="{{ 'SEARCH' | translate }}">
                    <span class="input-bar"></span>
                </div> -->
            </div>
            <div class="col-lg-6">
                <ul class="nav-right pull-right list-unstyled">
                    <li>
                        <span style="display: inline-block; padding-top: 22px; padding-left: 24px; padding-right: 24px; font-size: 14px;">12.5 Ξ</span>
                    </li>
                    <li>
                        <!--  <md-select placeholder="brighteye" style="margin: 16px 22px 0 22px; z-index: 1111;">
                             <md-option>brighteye</md-option>
                             <md-option>testacct</md-option>
                             <md-option>stash</md-option> -->
                    </li>
                </ul>
            </div>
        </div>
        <div class="row">
            <div class="col-lg-12">
                <h1>Signals</h1>
                <p style="margin-left: 16px;">SANbase will generate signals when actionable intelligence or events occur in the crypto-markets. </p>

            </div>
        </div>
        <div class="row">
            <div class="col-12">
                <div class="panel">

                    <div class="signals-form">
                        <h2><span>Join our <strong>SANbase Signals</strong> email list</span> <span>to receive pre-release alpha and beta signals:</span></h2>
                        <!-- Begin MailChimp Signup Form -->
                        <link href="http://cdn-images.mailchimp.com/embedcode/slim-10_7.css" rel="stylesheet" type="text/css">
                        <div id="mc_embed_signup">
                            <form action="http://santiment.us14.list-manage.com/subscribe/post?u=122a728fd98df22b204fa533c&amp;id=80b55fcb45" method="post" id="mc-embedded-subscribe-form" name="mc-embedded-subscribe-form" class="validate" target="_blank" novalidate>
                                <div id="mc_embed_signup_scroll">
                                    <input type="email" value="" name="EMAIL" class="email" id="mce-EMAIL" placeholder="Your email address" required>
                                    <!-- real people should not fill this in and expect good things - do not remove this or risk form bot signups-->
                                    <div style="position: absolute; left: -5000px;" aria-hidden="true"><input type="text" name="b_122a728fd98df22b204fa533c_80b55fcb45" tabindex="-1" value=""></div>
                                    <div class="clear"><input type="submit" value="Subscribe" name="subscribe" id="mc-embedded-subscribe" class="button"></div>
                                </div>
                            </form>
                        </div>
                        <!--End mc_embed_signup-->
                    </div>

                    <div class="narrow">
                        <h3>Welcome, community! Santiment will be developing signals over the next few months and would love your help evaluating and testing the feature.</h3>

                        <p><strong>Get a first glimpse into what SANbase email signals will look like.</strong> A signal's main purpose is to send a notification
                            when something potentially important has happened in the crypto-markets.
                            Signals will help you distinguish between mere noise (80% of the chatter) and valuable insights into what is going on in the marketplace.</p>

                        <p>A few examples:</p>
                        <ul>
                            <li>Team wallet money has hit an exchange</li>
                            <li>Whales (long-term holders) moved part of their holdings to an exchange</li>
                            <li>Trading volume of a particular asset has exceeded an average by 50%</li>
                            <li>Crowd sentiment has reached an extreme (positive or negative)</li>
                        </ul>

                        <p>Today, all signals you'll receive from this list are free. In the future, some signals will remain free
                            (like the first one), for others one will need to pay in SANs (like the last one).
                            Signals can be general, but will often be related to a specific asset.
                            We'll be looking at asset filtering in future revisions.</p>
                        <br />
                        <p><em><strong>One important note:</strong> To start, Santiment will provide an initial set of signals, yet we also
                            will encourage the community (market analysts, data scientists, etc) to provide their own signals on the
                            platform. We are gathering a unique set of data for the crypto space and will open access to it through our SAN-api.
                            Come join us early.</em></p>

                    </div>

                </div>
            </div>
        </div>
    </div>
   `}} />
  </div>
)

export default Index
